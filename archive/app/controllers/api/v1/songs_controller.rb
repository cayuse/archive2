class Api::V1::SongsController < ApplicationController
  include EncryptedTokenAuthentication
  
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_encrypted_token_user!, only: []  # Require auth for all actions
  before_action :set_song, only: [:show, :download, :stream]
  before_action :ensure_upload_permission!, only: [:bulk_upload, :bulk_create, :bulk_update, :direct_upload, :create_from_blob]

  def index
    # Parse pagination params
    page = params[:page]&.to_i || 1
    limit = params[:limit]&.to_i || 50
    limit = [[limit, 1].max, 100].min # Clamp between 1 and 100
    
    # Parse sorting params
    sort_by = params[:sort_by] || 'created_at'
    sort_order = params[:sort_order]&.downcase == 'asc' ? 'asc' : 'desc'
    
    # Get songs with pagination
    songs = Song.includes(:artist, :album, :genre)
                .order("#{sort_by} #{sort_order}")
                .page(page)
                .per(limit)
    
    render json: {
      success: true,
      songs: songs.map do |song|
        {
          id: song.id,
          title: song.title,
          artist: song.artist&.name,
          album: song.album&.title,
          genre: song.genre&.name,
          duration: song.duration,
          track_number: song.track_number,
          file_format: song.file_format,
          processing_status: song.processing_status,
          created_at: song.created_at
        }
      end,
      pagination: {
        current_page: songs.current_page,
        total_pages: songs.total_pages,
        total_count: songs.total_count,
        limit: limit
      }
    }
  end

  def show
    include_binary = params[:include] == 'binary'
    
    if include_binary
      # Return binary data directly
      send_data @song.audio_file.download, 
                filename: "#{@song.artist.name} - #{@song.title}.#{@song.file_format}",
                type: @song.audio_file.content_type
    else
      # Return JSON metadata
      render json: {
        success: true,
        song: {
          id: @song.id,
          title: @song.title,
          artist: @song.artist.name,
          album: @song.album.title,
          genre: @song.genre.name,
          duration: @song.duration,
          file_format: @song.file_format,
          file_size: @song.audio_file.byte_size,
          download_url: api_v1_song_download_url(@song),
          stream_url: api_v1_song_stream_url(@song)
        }
      }
    end
  end

  def download
    send_data @song.audio_file.download,
              filename: "#{@song.artist.name} - #{@song.title}.#{@song.file_format}",
              type: @song.audio_file.content_type
  end

  def stream
    # Support HTTP Range requests for progressive download
    if request.headers['Range']
      range = request.headers['Range']
      file_size = @song.audio_file.byte_size
      
      # Parse range header
      if range =~ /bytes=(\d+)-(\d*)/
        start_byte = $1.to_i
        end_byte = $2.empty? ? file_size - 1 : $2.to_i
        
        response.headers['Content-Range'] = "bytes #{start_byte}-#{end_byte}/#{file_size}"
        response.headers['Accept-Ranges'] = 'bytes'
        response.headers['Content-Length'] = (end_byte - start_byte + 1).to_s
        
        # Stream partial content
        send_data @song.audio_file.download(start_byte, end_byte - start_byte + 1),
                  status: 206,
                  type: @song.audio_file.content_type
      end
    else
      # Stream full file
      send_data @song.audio_file.download,
                type: @song.audio_file.content_type
    end
  end

  def bulk_upload
    # Check if audio file is provided
    unless params[:audio_file].present?
      render json: {
        success: false,
        message: "No audio file provided"
      }, status: :unprocessable_entity
      return
    end

    begin
      # Create new song with uploaded file
      @song = Song.new
      @song.audio_file.attach(params[:audio_file])
      
      # Store original filename
      @song.original_filename = params[:filename] || params[:audio_file].original_filename
      
      # Set optional metadata if provided
      @song.title = params[:title] if params[:title].present?
      @song.track_number = params[:track_number] if params[:track_number].present?
      @song.duration = params[:duration] if params[:duration].present?
      
      # Handle artist
      if params[:artist_name].present?
        @song.artist = Artist.find_or_create_by!(name: params[:artist_name])
      end
      
      # Handle album
      if params[:album_title].present?
        @song.album = Album.find_or_create_by!(title: params[:album_title])
      end
      
      # Handle genre
      if params[:genre_name].present?
        @song.genre = Genre.find_or_create_by!(name: params[:genre_name])
      end
      
      # Set processing status
      @song.processing_status = 'needs_review'
      
      if @song.save
        # Extract metadata from file if not skipped
        unless params[:skip_post_processing] == 'true' || params[:skip_post_processing] == true
          if @song.audio_file.attached?
            metadata = @song.extract_metadata_from_file
            
            if metadata[:error].blank?
              # Update with extracted metadata
              @song.title ||= metadata[:title] if metadata[:title].present?
              @song.track_number ||= metadata[:track_number] if metadata[:track_number].present?
              @song.duration ||= metadata[:duration] if metadata[:duration].present?
              @song.file_format = metadata[:file_format] if metadata[:file_format].present?
              @song.file_size = metadata[:file_size] if metadata[:file_size].present?
              
              # Handle artist from metadata
              if metadata[:artist].present? && @song.artist.nil?
                @song.artist = Artist.find_or_create_by!(name: metadata[:artist])
              end
              
              # Handle album from metadata
              if metadata[:album].present? && @song.album.nil?
                @song.album = Album.find_or_create_by!(title: metadata[:album])
              end
              
              # Handle genre from metadata
              if metadata[:genre].present? && @song.genre.nil?
                @song.genre = Genre.find_or_create_by!(name: metadata[:genre])
              end
              
              # Determine processing status based on metadata completeness
              if @song.has_complete_metadata?
                @song.processing_status = 'completed'
              else
                @song.processing_status = 'needs_review'
              end
              
              @song.save
            else
              @song.processing_status = 'failed'
              @song.processing_error = metadata[:error]
              @song.save
            end
          end
        end
        
        render json: {
          success: true,
          message: "Song uploaded successfully",
          song: {
            id: @song.id,
            title: @song.title,
            artist: @song.artist&.name,
            album: @song.album&.title,
            genre: @song.genre&.name,
            processing_status: @song.processing_status,
            created_at: @song.created_at
          }
        }, status: :created
      else
        render json: {
          success: false,
          message: "Failed to save song",
          errors: @song.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "Bulk upload error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        message: "Upload failed: #{e.message}"
      }, status: :internal_server_error
    end
  end

  private

  def set_song
    @song = Song.includes(:artist, :album, :genre).find(params[:id])
  end
  
  def ensure_upload_permission!
    unless @current_api_user&.moderator? || @current_api_user&.admin?
      render json: {
        success: false,
        message: "Insufficient permissions. Moderator or admin role required."
      }, status: :forbidden
    end
  end
end