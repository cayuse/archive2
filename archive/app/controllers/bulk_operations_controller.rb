class BulkOperationsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_bulk_operations!
  
  def index
    # Show bulk operations dashboard
  end
  
  def upload_csv
    if params[:file].blank?
      flash[:alert] = "Please select a file to upload"
      redirect_to bulk_operations_path
      return
    end
    
    file = params[:file]
    
    unless file.content_type.include?('csv')
      flash[:alert] = "Please upload a CSV file"
      redirect_to bulk_operations_path
      return
    end
    
    begin
      # Process CSV upload
      result = process_csv_upload(file)
      
      if result[:success]
        flash[:notice] = "Successfully imported #{result[:created_count]} songs. #{result[:errors].length} errors occurred."
      else
        flash[:alert] = "Import failed: #{result[:error]}"
      end
    rescue => e
      flash[:alert] = "Error processing file: #{e.message}"
    end
    
    redirect_to bulk_operations_path
  end
  
  def export_csv
    songs = Song.includes(:artist, :album, :genre).all
    csv_data = generate_csv(songs)
    
    send_data csv_data, 
              filename: "songs_export_#{Date.current}.csv",
              type: 'text/csv'
  end
  
  def bulk_delete
    song_ids = params[:song_ids]&.split(',')&.map(&:to_i) || []
    
    if song_ids.empty?
      flash[:alert] = "Please select songs to delete"
      redirect_to bulk_operations_path
      return
    end
    
    destroyed_count = 0
    errors = []
    
    song_ids.each do |id|
      song = Song.find_by(id: id)
      if song
        if song.destroy
          destroyed_count += 1
        else
          errors << "Could not delete song #{id}"
        end
      else
        errors << "Song #{id} not found"
      end
    end
    
    if errors.any?
      flash[:alert] = "Deleted #{destroyed_count} songs. Errors: #{errors.join(', ')}"
    else
      flash[:notice] = "Successfully deleted #{destroyed_count} songs"
    end
    
    redirect_to bulk_operations_path
  end
  
  private
  
  def authorize_bulk_operations!
    unless current_user&.moderator?
      flash[:alert] = "You don't have permission to perform bulk operations"
      redirect_to root_path
    end
  end
  
  def process_csv_upload(file)
    require 'csv'
    
    csv_data = CSV.parse(file.read, headers: true)
    created_songs = []
    errors = []
    
    csv_data.each_with_index do |row, index|
      begin
        song_data = {
          title: row['title'],
          track_number: row['track_number'],
          duration: row['duration'],
          file_format: row['file_format'],
          file_size: row['file_size'],
          artist_name: row['artist_name'],
          album_title: row['album_title'],
          album_release_date: row['album_release_date'],
          genre_name: row['genre_name']
        }
        
        song = create_song_from_data(song_data)
        if song.persisted?
          created_songs << song
        else
          errors << { row: index + 2, errors: song.errors.full_messages }
        end
      rescue => e
        errors << { row: index + 2, error: e.message }
      end
    end
    
    {
      success: true,
      created_count: created_songs.length,
      errors: errors
    }
  rescue => e
    {
      success: false,
      error: e.message
    }
  end
  
  def create_song_from_data(data)
    # Find or create artist
    artist = Artist.find_or_create_by(name: data[:artist_name]) if data[:artist_name]
    
    # Find or create album
    album = nil
    if data[:album_title] && artist
      album = Album.find_or_create_by(title: data[:album_title], artist: artist) do |a|
        a.release_date = data[:album_release_date] if data[:album_release_date]
      end
    end
    
    # Find or create genre
    genre = Genre.find_or_create_by(name: data[:genre_name]) if data[:genre_name]
    
    # Create song
    song = Song.new(
      title: data[:title],
      track_number: data[:track_number],
      duration: data[:duration],
      file_format: data[:file_format],
      file_size: data[:file_size],
      album: album,
      genre: genre
    )
    
    song.save
    song
  end
  
  def generate_csv(songs)
    require 'csv'
    
    CSV.generate do |csv|
      csv << ['id', 'title', 'track_number', 'duration', 'file_format', 'file_size', 
              'artist_name', 'album_title', 'album_release_date', 'genre_name', 
              'created_at', 'updated_at']
      
      songs.each do |song|
        csv << [
          song.id,
          song.title,
          song.track_number,
          song.duration,
          song.file_format,
          song.file_size,
          song.artist&.name,
          song.album&.title,
          song.album&.release_date,
          song.genre&.name,
          song.created_at,
          song.updated_at
        ]
      end
    end
  end
end 