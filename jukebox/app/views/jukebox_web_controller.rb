  # GET /live/status.json - JSON API for player status
  def live_status
    # Get player status from Redis (same as the Python player writes)
    redis = Redis.new(host: ENV.fetch('REDIS_HOST', 'localhost'), 
                      port: ENV.fetch('REDIS_PORT', '6379').to_i, 
                      db: ENV.fetch('REDIS_DB', '1').to_i)
    
    player_status = redis.hgetall('jukebox:player_status')
    current_song_json = redis.get('jukebox:current_song')
    
    # Parse current song if available
    current_song = nil
    if current_song_json
      begin
        current_song = JSON.parse(current_song_json)
      rescue JSON::ParserError
        current_song = nil
      end
    end
    
    # If no current song from Redis, try to get the last played song
    if current_song.nil?
      last_played = JukeboxPlayedSong.order(played_at: :desc).includes(song: [:artist, :album]).first
      if last_played&.song
        current_song = {
          id: last_played.song.id,
          title: last_played.song.title,
          artist: last_played.song.artist&.name,
          album: last_played.song.album&.title,
          duration: last_played.song.duration
        }
      end
    end
    
    render json: {
      player_status: player_status,
      current_song: current_song
    }
  end
