require 'mpd'

class MPDClient
  attr_reader :mpd, :connected, :last_status, :last_queue_length

  def initialize(host = 'localhost', port = 6600, password = nil)
    @host = host
    @port = port
    @password = password
    @connected = false
    @last_status = {}
    @last_queue_length = 0
    @shutdown = false
    @reconnect_attempts = 0
    @max_reconnect_attempts = 5
    @reconnect_delay = 5
  end

  def connect
    begin
      @mpd = MPD.new(@host, @port)
      @mpd.connect
      
      if @password
        @mpd.password(@password)
      end

      # Configure MPD settings
      configure_mpd
      
      @connected = true
      @reconnect_attempts = 0
      Rails.logger.info "Connected to MPD at #{@host}:#{@port}"
      
      # Report initial volume
      report_volume
      
    rescue => e
      Rails.logger.error "Failed to connect to MPD: #{e.message}"
      @connected = false
      raise
    end
  end

  def disconnect
    return unless @mpd && @connected
    
    begin
      @mpd.disconnect
      @connected = false
      Rails.logger.info "Disconnected from MPD"
    rescue => e
      Rails.logger.error "Error disconnecting from MPD: #{e.message}"
    end
  end

  def reconnect
    return if @reconnect_attempts >= @max_reconnect_attempts
    
    @reconnect_attempts += 1
    Rails.logger.info "Attempting to reconnect to MPD (attempt #{@reconnect_attempts}/#{@max_reconnect_attempts})"
    
    begin
      disconnect
      sleep @reconnect_delay
      connect
    rescue => e
      Rails.logger.error "Reconnection failed: #{e.message}"
      if @reconnect_attempts < @max_reconnect_attempts
        # Exponential backoff
        @reconnect_delay = [@reconnect_delay * 2, 60].min
        reconnect
      else
        Rails.logger.error "Max reconnection attempts reached. MPD client will stop trying."
      end
    end
  end

  def poll_and_broadcast
    return unless @connected && !@shutdown
    
    begin
      # Get current status
      status = @mpd.status
      current_song = @mpd.current_song
      queue = @mpd.queue
      
      # Check if we need to refill the queue
      queue_length = queue.length
      if queue_length < 2 && status['state'] == 'play'
        Rails.logger.info "Queue low (#{queue_length} songs), triggering refill"
        AddSongJob.perform_later
      end
      
      # Check if status has changed
      status_changed = status != @last_status || queue_length != @last_queue_length
      
      if status_changed
        @last_status = status
        @last_queue_length = queue_length
        
        # Broadcast via ActionCable
        broadcast_status(status, current_song, queue)
        
        # Update Redis for compatibility
        update_redis_status(status, current_song, queue)
      end
      
    rescue => e
      Rails.logger.error "MPD polling error: #{e.message}"
      @connected = false
      reconnect
    end
  end

  def start_polling
    return if @shutdown
    
    Rails.logger.info "Starting MPD polling thread"
    
    @polling_thread = Thread.new do
      loop do
        break if @shutdown
        
        if @connected
          poll_and_broadcast
        else
          begin
            connect
          rescue => e
            Rails.logger.error "Failed to connect to MPD: #{e.message}"
            sleep @reconnect_delay
          end
        end
        
        sleep 1
      end
    end
    
    @polling_thread.abort_on_exception = true
  end

  def stop_polling
    @shutdown = true
    
    if @polling_thread
      @polling_thread.exit
      @polling_thread = nil
    end
    
    disconnect
    Rails.logger.info "MPD polling stopped"
  end

  def get_status
    return { error: 'Not connected to MPD', connected: false } unless @connected
    
    begin
      status = @mpd.status
      current_song = @mpd.current_song
      queue = @mpd.queue
      
      {
        connected: true,
        state: status['state'] || 'unknown',
        volume: (status['volume'] || '0').to_i,
        elapsed: (status['elapsed'] || '0').to_f,
        duration: (status['duration'] || '0').to_f,
        progress: calculate_progress(status),
        remaining: calculate_remaining(status),
        current_song: current_song ? song_to_hash(current_song) : nil,
        playlist_length: queue.length,
        repeat: status['repeat'] == '1',
        random: status['random'] == '1',
        single: status['single'] == '1',
        consume: status['consume'] == '1',
        crossfade: (status['xfade'] || '0').to_i,
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error getting MPD status: #{e.message}"
      { error: e.message, connected: false }
    end
  end

  def get_volume
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      status = @mpd.status
      volume = (status['volume'] || '0').to_i
      
      {
        volume: volume,
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error getting volume: #{e.message}"
      { error: e.message }
    end
  end

  def set_volume(volume)
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      # Clamp volume to 0-100
      volume = [[0, volume].max, 100].min
      
      @mpd.setvol(volume)
      report_volume(volume)
      
      {
        volume: volume,
        success: true,
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error setting volume: #{e.message}"
      { error: e.message }
    end
  end

  def get_current_song
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      status = @mpd.status
      return { error: 'No song currently playing' } unless status['state'] == 'play'
      
      current_song = @mpd.current_song
      return { error: 'Could not get current song info' } unless current_song
      
      elapsed = (status['elapsed'] || '0').to_f
      duration = (status['duration'] || '0').to_f
      
      {
        title: current_song['title'] || 'Unknown',
        artist: current_song['artist'] || 'Unknown',
        album: current_song['album'] || 'Unknown',
        duration: duration,
        elapsed: elapsed,
        remaining: [0, duration - elapsed].max,
        progress: calculate_progress(status),
        file: current_song['file'] || '',
        id: current_song['id'] || '',
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error getting current song: #{e.message}"
      { error: e.message }
    end
  end

  def get_progress
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      status = @mpd.status
      return { error: 'No MPD status' } unless status
      
      elapsed = (status['elapsed'] || '0').to_f
      duration = (status['duration'] || '0').to_f
      progress = calculate_progress(status)
      
      {
        elapsed: elapsed,
        duration: duration,
        remaining: [0, duration - elapsed].max,
        progress: progress,
        state: status['state'] || 'unknown',
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error getting progress: #{e.message}"
      { error: e.message }
    end
  end

  def get_queue
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      queue = @mpd.queue
      
      queue_data = queue.map do |item|
        {
          id: item['id'] || '',
          title: item['title'] || 'Unknown',
          artist: item['artist'] || 'Unknown',
          album: item['album'] || 'Unknown',
          duration: (item['duration'] || '0').to_i,
          file: item['file'] || '',
          pos: (item['pos'] || '0').to_i
        }
      end
      
      {
        queue: queue_data,
        length: queue.length,
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error getting queue: #{e.message}"
      { error: e.message }
    end
  end

  def play_song(stream_url, force_play = false)
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      # If nothing queued, add and play; otherwise add only (for crossfade)
      status = @mpd.status
      playlist_length = (status['playlistlength'] || '0').to_i
      
      if force_play
        @mpd.clear
        @mpd.add(stream_url)
        @mpd.play
        Rails.logger.info "MPD play issued (force)"
      else
        if playlist_length == 0
          @mpd.clear
          @mpd.add(stream_url)
          @mpd.play
          Rails.logger.info "MPD play issued"
        else
          @mpd.add(stream_url)
        end
      end
      
      {
        success: true,
        message: "Song queued successfully",
        timestamp: Time.current.to_f
      }
    rescue => e
      Rails.logger.error "Error playing song: #{e.message}"
      { error: e.message }
    end
  end

  def next_song
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      @mpd.next
      { success: true, message: "Next song" }
    rescue => e
      Rails.logger.error "Error skipping to next song: #{e.message}"
      { error: e.message }
    end
  end

  def previous_song
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      @mpd.previous
      { success: true, message: "Previous song" }
    rescue => e
      Rails.logger.error "Error going to previous song: #{e.message}"
      { error: e.message }
    end
  end

  def pause
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      @mpd.pause(1)
      { success: true, message: "Paused" }
    rescue => e
      Rails.logger.error "Error pausing: #{e.message}"
      { error: e.message }
    end
  end

  def resume
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      @mpd.pause(0)
      { success: true, message: "Resumed" }
    rescue => e
      Rails.logger.error "Error resuming: #{e.message}"
      { error: e.message }
    end
  end

  def stop
    return { error: 'Not connected to MPD' } unless @connected
    
    begin
      @mpd.stop
      { success: true, message: "Stopped" }
    rescue => e
      Rails.logger.error "Error stopping: #{e.message}"
      { error: e.message }
    end
  end

  private

  def configure_mpd
    # Ensure at least one output is enabled
    begin
      outputs = @mpd.outputs
      outputs.each do |output|
        if output['outputenabled'] == '0'
          @mpd.enableoutput(output['outputid'].to_i)
        end
      end
    rescue => e
      Rails.logger.warn "Could not configure MPD outputs: #{e.message}"
    end

    # Configure MPD settings (best-effort)
    begin
      @mpd.crossfade(6)
    rescue => e
      Rails.logger.warn "Could not set crossfade: #{e.message}"
    end

    begin
      @mpd.setvol(80)
    rescue => e
      Rails.logger.warn "Could not set initial volume: #{e.message}"
    end

    # Ensure MPD does not loop old items; consume removes played items
    begin
      @mpd.repeat(0)
      @mpd.random(0)
      @mpd.single(0)
      @mpd.consume(1)
    rescue => e
      Rails.logger.warn "Could not configure MPD playback settings: #{e.message}"
    end
  end

  def calculate_progress(status)
    elapsed = (status['elapsed'] || '0').to_f
    duration = (status['duration'] || '0').to_f
    
    if duration > 0
      ((elapsed / duration) * 100).round(1)
    else
      0
    end
  end

  def calculate_remaining(status)
    elapsed = (status['elapsed'] || '0').to_f
    duration = (status['duration'] || '0').to_f
    
    [0, duration - elapsed].max
  end

  def song_to_hash(song)
    {
      title: song['title'] || 'Unknown',
      artist: song['artist'] || 'Unknown',
      album: song['album'] || 'Unknown',
      duration: (song['duration'] || '0').to_i,
      file: song['file'] || '',
      id: song['id'] || ''
    }
  end

  def broadcast_status(status, current_song, queue)
    return unless defined?(ActionCable)
    
    begin
      ActionCable.server.broadcast('player_channel', {
        status: status,
        current_song: current_song ? song_to_hash(current_song) : nil,
        queue_length: queue.length,
        timestamp: Time.current.to_f
      })
    rescue => e
      Rails.logger.error "Error broadcasting via ActionCable: #{e.message}"
    end
  end

  def update_redis_status(status, current_song, queue)
    return unless defined?(Redis)
    
    begin
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      # Update current song
      if current_song
        redis.set('jukebox:current_song', current_song.to_json)
      end
      
      # Update queue length
      redis.set('jukebox:queue_length', queue.length)
      
      # Update status
      redis.set('jukebox:status', status.to_json)
      
    rescue => e
      Rails.logger.error "Error updating Redis: #{e.message}"
    end
  end

  def report_volume(volume = nil)
    return unless defined?(Redis)
    
    begin
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      if volume.nil?
        status = @mpd.status
        volume = (status['volume'] || '0').to_i
      end
      
      redis.set('jukebox:current_volume', volume)
      Rails.logger.info "Volume set to #{volume}%"
    rescue => e
      Rails.logger.error "Failed to report volume to Redis: #{e.message}"
    end
  end
end
