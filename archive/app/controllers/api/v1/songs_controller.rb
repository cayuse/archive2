class Api::V1::SongsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!
  before_action :ensure_upload_permission!

  def index
    songs = Song.includes(:artist, :album, :genre)
                .order(created_at: :desc)
                .limit(params[:limit] || 50)
                .offset(params[:offset] || 0)

    render json: {
      success: true,
      songs: songs.map { |song| song_to_json(song) },
      total: Song.count,
      limit: params[:limit] || 50,
      offset: params[:offset] || 0
    }
  end

  def show
    song = Song.includes(:artist, :album, :genre).find(params[:id])
    render json: {
      success: true,
      song: song_to_json(song)
    }
  end

  def bulk_upload
    unless params[:audio_file]
      render json: {
        success: false,
        message: "No audio file provided"
      }, status: :bad_request
      return
    end

    audio_file = params[:audio_file]
    
    # Validate file type
    unless valid_audio_file?(audio_file)
      render json: {
        success: false,
        message: "Invalid audio file format"
      }, status: :bad_request
      return
    end

    begin
      # Create song record
      song = Song.new(
        title: extract_title_from_filename(audio_file.original_filename),
        processing_status: 'processing',
        user: @current_api_user
      )

      # Attach audio file
      song.audio_file.attach(audio_file)

      if song.save
        # Extract metadata asynchronously
        ExtractMetadataJob.perform_later(song.id)
        
        render json: {
          success: true,
          message: "Song uploaded successfully",
          song: {
            id: song.id,
            title: song.title,
            processing_status: song.processing_status,
            created_at: song.created_at
          }
        }, status: :created
      else
        render json: {
          success: false,
          message: "Failed to save song",
          errors: song.errors.full_messages
        }, status: :unprocessable_entity
      end

    rescue => e
      Rails.logger.error "Bulk upload error: #{e.message}"
      render json: {
        success: false,
        message: "Upload failed: #{e.message}"
      }, status: :internal_server_error
    end
  end

  def bulk_create
    # Handle multiple songs at once
    songs_data = params[:songs] || []
    
    if songs_data.empty?
      render json: {
        success: false,
        message: "No songs data provided"
      }, status: :bad_request
      return
    end

    results = []
    success_count = 0
    error_count = 0

    songs_data.each do |song_data|
      begin
        song = Song.new(song_params(song_data))
        song.user = @current_api_user
        
        if song.save
          success_count += 1
          results << { success: true, id: song.id, title: song.title }
        else
          error_count += 1
          results << { 
            success: false, 
            errors: song.errors.full_messages,
            title: song_data[:title] || 'Unknown'
          }
        end
      rescue => e
        error_count += 1
        results << { 
          success: false, 
          error: e.message,
          title: song_data[:title] || 'Unknown'
        }
      end
    end

    render json: {
      success: true,
      message: "Bulk create completed",
      results: results,
      summary: {
        total: songs_data.length,
        successful: success_count,
        failed: error_count
      }
    }
  end

  def bulk_update
    # Update multiple songs at once
    songs_data = params[:songs] || []
    
    if songs_data.empty?
      render json: {
        success: false,
        message: "No songs data provided"
      }, status: :bad_request
      return
    end

    results = []
    success_count = 0
    error_count = 0

    songs_data.each do |song_data|
      begin
        song = Song.find(song_data[:id])
        
        if song.update(song_params(song_data))
          success_count += 1
          results << { success: true, id: song.id, title: song.title }
        else
          error_count += 1
          results << { 
            success: false, 
            errors: song.errors.full_messages,
            id: song.id,
            title: song.title
          }
        end
      rescue ActiveRecord::RecordNotFound
        error_count += 1
        results << { 
          success: false, 
          error: "Song not found",
          id: song_data[:id]
        }
      rescue => e
        error_count += 1
        results << { 
          success: false, 
          error: e.message,
          id: song_data[:id]
        }
      end
    end

    render json: {
      success: true,
      message: "Bulk update completed",
      results: results,
      summary: {
        total: songs_data.length,
        successful: success_count,
        failed: error_count
      }
    }
  end

  def bulk_destroy
    song_ids = params[:song_ids] || []
    
    if song_ids.empty?
      render json: {
        success: false,
        message: "No song IDs provided"
      }, status: :bad_request
      return
    end

    songs = Song.where(id: song_ids)
    deleted_count = songs.destroy_all.length

    render json: {
      success: true,
      message: "Bulk delete completed",
      deleted_count: deleted_count,
      requested_count: song_ids.length
    }
  end

  def export
    songs = Song.includes(:artist, :album, :genre).all
    
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Title', 'Artist', 'Album', 'Genre', 'Duration', 'Processing Status', 'Created At']
      
      songs.each do |song|
        csv << [
          song.id,
          song.title,
          song.artist&.name,
          song.album&.name,
          song.genre&.name,
          song.duration,
          song.processing_status,
          song.created_at
        ]
      end
    end

    send_data csv_data, 
              filename: "songs_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
              type: 'text/csv'
  end

  private

  def authenticate_api_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { success: false, message: "Missing API token" }, status: :unauthorized
      return
    end

    begin
      payload = JSON.parse(Base64.urlsafe_decode64(token))
      
      if payload['exp'] && Time.current.to_i > payload['exp']
        render json: { success: false, message: "API token expired" }, status: :unauthorized
        return
      end
      
      @current_api_user = User.find(payload['user_id'])
      
      unless @current_api_user
        render json: { success: false, message: "Invalid API token" }, status: :unauthorized
        return
      end
      
    rescue => e
      render json: { success: false, message: "Invalid API token" }, status: :unauthorized
      return
    end
  end

  def ensure_upload_permission!
    unless @current_api_user.moderator? || @current_api_user.admin?
      render json: {
        success: false,
        message: "Insufficient permissions for upload"
      }, status: :forbidden
      return
    end
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end

  def valid_audio_file?(file)
    return false unless file.respond_to?(:content_type)
    
    audio_types = [
      'audio/mpeg',
      'audio/wav',
      'audio/flac',
      'audio/mp4',
      'audio/ogg',
      'audio/aac'
    ]
    
    audio_types.include?(file.content_type)
  end

  def extract_title_from_filename(filename)
    # Remove extension and clean up the filename
    title = File.basename(filename, File.extname(filename))
    title.gsub(/[_-]/, ' ').strip
  end

  def song_params(data)
    data.permit(:title, :artist_id, :album_id, :genre_id, :processing_status, :notes)
  end

  def song_to_json(song)
    {
      id: song.id,
      title: song.title,
      artist: song.artist&.name,
      album: song.album&.name,
      genre: song.genre&.name,
      duration: song.duration,
      processing_status: song.processing_status,
      created_at: song.created_at,
      updated_at: song.updated_at,
      audio_url: song.audio_file.attached? ? rails_blob_url(song.audio_file) : nil
    }
  end
end 