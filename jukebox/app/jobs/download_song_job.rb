class DownloadSongJob < ApplicationJob
  queue_as :default
  
  def perform(song_id)
    song = Song.find(song_id)
    
    # Skip if already cached
    return if song.cached?
    
    # Create or find cached song record
    cached_song = JukeboxCachedSong.find_or_create_by(song_id: song_id) do |cs|
      cs.status = 'downloading'
      cs.started_at = Time.current
    end
    
    # Skip if already downloading
    return if cached_song.downloading?
    
    begin
      Rails.logger.info "Starting download for song: #{song.title}"
      
      # Update status
      cached_song.update!(
        status: 'downloading',
        started_at: Time.current,
        error_message: nil
      )
      
      # Download the song from archive
      download_song_from_archive(song, cached_song)
      
      # Update status to completed
      cached_song.update!(
        status: 'completed',
        completed_at: Time.current,
        file_size: File.size(cached_song.local_path)
      )
      
      Rails.logger.info "Successfully downloaded song: #{song.title}"
      
    rescue => e
      Rails.logger.error "Failed to download song #{song.title}: #{e.message}"
      
      # Update status to failed
      cached_song.update!(
        status: 'failed',
        error_message: e.message,
        completed_at: Time.current
      )
      
      # Re-raise for job retry
      raise e
    end
  end
  
  private
  
  def download_song_from_archive(song, cached_song)
    # Construct the archive URL for the song
    archive_url = construct_archive_url(song)
    
    # Create local directory if it doesn't exist
    local_dir = Rails.root.join('storage', 'cached_songs')
    FileUtils.mkdir_p(local_dir)
    
    # Generate local filename
    local_filename = generate_local_filename(song)
    local_path = local_dir.join(local_filename)
    
    # Download the file
    download_file(archive_url, local_path)
    
    # Update cached song record
    cached_song.update!(
      local_path: local_path.to_s,
      original_path: song.file_path
    )
  end
  
  def construct_archive_url(song)
    archive_base_url = ENV.fetch('ARCHIVE_SERVER_URL', 'http://localhost:3000')
    
    # Use the archive's API to get the download URL
    # This assumes the archive has an API endpoint for song downloads
    "#{archive_base_url}/api/v1/audio_files/#{song.id}/download"
  end
  
  def generate_local_filename(song)
    # Create a safe filename from song metadata
    safe_title = song.title.gsub(/[^a-zA-Z0-9\s\-_\.]/, '')
    safe_artist = song.artist&.gsub(/[^a-zA-Z0-9\s\-_\.]/, '') || 'Unknown'
    
    # Get file extension from original path
    extension = File.extname(song.file_path) || '.mp3'
    
    # Create filename: artist - title.ext
    "#{safe_artist} - #{safe_title}#{extension}"
  end
  
  def download_file(url, local_path)
    require 'net/http'
    require 'uri'
    
    uri = URI(url)
    
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      
      # Add authentication if needed
      if ENV['ARCHIVE_API_KEY']
        request['Authorization'] = "Bearer #{ENV['ARCHIVE_API_KEY']}"
      end
      
      http.request(request) do |response|
        if response.code == '200'
          File.open(local_path, 'wb') do |file|
            response.read_body do |chunk|
              file.write(chunk)
            end
          end
        else
          raise "HTTP #{response.code}: #{response.message}"
        end
      end
    end
  end
end 