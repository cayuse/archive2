class Api::V1::SongsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_song, only: [:show, :download, :stream]

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

  private

  def set_song
    @song = Song.includes(:artist, :album, :genre).find(params[:id])
  end
end