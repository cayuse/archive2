class Api::V1::AudioFilesController < ApplicationController
  include EncryptedTokenAuthentication
  
  skip_before_action :verify_authenticity_token
  before_action :set_song, only: [:show, :stream, :download]
  
  def show
    render json: {
      song_id: @song.id,
      title: @song.title,
      artist: @song.artist&.name,
      album: @song.album&.title,
      duration: @song.duration,
      file_format: @song.file_format,
      file_size: @song.file_size,
      stream_url: api_v1_audio_file_stream_url(@song),
      download_url: api_v1_audio_file_download_url(@song)
    }
  end
  
  def stream
    unless @song.audio_file.attached?
      render json: { error: 'Audio file not found' }, status: :not_found
      return
    end
    
    # Set appropriate headers for streaming
    response.headers['Content-Type'] = @song.audio_file.content_type
    response.headers['Accept-Ranges'] = 'bytes'
    
    # Handle range requests for seeking
    if request.headers['Range']
      handle_range_request
    else
      # Stream the entire file
      stream_file(@song.audio_file)
    end
  end
  
  def download
    unless @song.audio_file.attached?
      render json: { error: 'Audio file not found' }, status: :not_found
      return
    end
    
    # Set headers for download
    filename = "#{@song.artist&.name} - #{@song.title}.#{@song.file_format || 'mp3'}"
    filename = filename.gsub(/[^0-9A-Za-z.\-]/, '_')
    
    response.headers['Content-Type'] = @song.audio_file.content_type
    response.headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""
    response.headers['Content-Length'] = @song.audio_file.byte_size
    
    # Stream the file for download
    stream_file(@song.audio_file)
  end
  
  private
  
  def set_song
    @song = Song.includes(:artist, :album).find(params[:id])
  end
  
  def handle_range_request
    range_header = request.headers['Range']
    file_size = @song.audio_file.byte_size
    
    # Parse range header (e.g., "bytes=0-1023")
    if range_header =~ /bytes=(\d+)-(\d*)/i
      start_byte = $1.to_i
      end_byte = $2.empty? ? file_size - 1 : $2.to_i
      
      # Validate range
      if start_byte >= file_size || end_byte >= file_size || start_byte > end_byte
        render status: :range_not_satisfiable
        return
      end
      
      content_length = end_byte - start_byte + 1
      
      # Set headers for partial content
      response.headers['Content-Range'] = "bytes #{start_byte}-#{end_byte}/#{file_size}"
      response.headers['Content-Length'] = content_length
      response.headers['Accept-Ranges'] = 'bytes'
      response.status = 206 # Partial Content
      
      # Stream the requested range
      stream_file_range(@song.audio_file, start_byte, end_byte)
    else
      render status: :bad_request
    end
  end
  
  def stream_file(attachment)
    # Stream the file in chunks to avoid memory issues
    attachment.open do |file|
      while (chunk = file.read(16.kilobytes))
        response.stream.write(chunk)
      end
    end
  ensure
    response.stream.close
  end
  
  def stream_file_range(attachment, start_byte, end_byte)
    attachment.open do |file|
      file.seek(start_byte)
      remaining_bytes = end_byte - start_byte + 1
      
      while remaining_bytes > 0
        chunk_size = [remaining_bytes, 16.kilobytes].min
        chunk = file.read(chunk_size)
        break unless chunk
        
        response.stream.write(chunk)
        remaining_bytes -= chunk.bytesize
      end
    end
  ensure
    response.stream.close
  end
end 