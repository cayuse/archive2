# =============================================================================
# MPD CLIENT - CRITICAL ARCHITECTURE NOTES
# =============================================================================
# 
# ⚠️  CRITICAL: POSTGRESQL CONNECTIVITY ⚠️ 
# 
# This MPD client connects to:
# - MPD: localhost:6600 (host MPD service) or Unix socket
# - PostgreSQL: db:5432 (Archive's container via Docker network)
# - Redis: redis:6379 (Archive's container via Docker network)
#
# DO NOT try to connect to localhost:5432 for PostgreSQL!
# DO NOT try to connect to localhost:6379 for Redis!
#
# The Rails app must be configured with:
# - POSTGRES_HOST=db (Docker service name)
# - REDIS_HOST=redis (Docker service name)
# - MPD_HOST=localhost (host MPD service) or MPD_SOCKET=/path/to/socket
#
# =============================================================================
# 
# REDIS USAGE EXPLANATION
# =============================================================================
# 
# Redis is still needed for:
# 1. State persistence across container restarts
# 2. Inter-process communication (Rails ↔ MPD poller)
# 3. Web interface state synchronization
# 4. Queue management and song selection
# 5. Volume and playback state caching
#
# Even though we eliminated the Python proxy, Redis provides:
# - Real-time state broadcasting via ActionCable
# - Persistent player state (volume, queue, current song)
# - Background job coordination
# - Web interface updates without polling
#
# =============================================================================

# Load MPD client gem only when needed to avoid eager-loading issues
# mpd_client 0.3.x is the modern, Ruby 3.2+ compatible MPD client

class MpdClient
  attr_reader :mpd, :connected, :last_status, :last_queue_length

  def initialize(host = 'localhost', port = 6600, password = nil, socket_path = nil)
    @host = host
    @port = port
    @password = password
    @socket_path = socket_path
    @connected = false
    @last_status = {}
    @last_queue_length = 0
    @shutdown = false
    @reconnect_attempts = 0
    @max_reconnect_attempts = 5
    @reconnect_delay = 5
    
    # Try to load MPD client gem on first use
    load_mpd_gem unless mpd_available?
  end

  def connect
    return { error: 'MPD client gem not available' } unless mpd_available?
    
    begin
      Rails.logger.info "MPD client gem available, attempting connection..." if defined?(Rails)
      
      if @socket_path
        Rails.logger.info "Attempting to connect to MPD via Unix socket at #{@socket_path}" if defined?(Rails)
        @mpd = MpdClient.new(socket: @socket_path)
      else
        Rails.logger.info "Attempting to connect to MPD at #{@host}:#{@port}" if defined?(Rails)
        @mpd = MpdClient.new(host: @host, port: @port)
      end
      
      Rails.logger.info "MPD client object created: #{@mpd.class}" if defined?(Rails)
      
      # Connect to MPD
      Rails.logger.info "Calling connect method..." if defined?(Rails)
      @mpd.connect
      Rails.logger.info "Connect method completed" if defined?(Rails)
      
      if @password
        Rails.logger.info "Setting password..." if defined?(Rails)
        @mpd.password(@password)
      end

      # Configure MPD settings
      Rails.logger.info "Configuring MPD..." if defined?(Rails)
      configure_mpd
      
      @connected = true
      @reconnect_attempts = 0
      
      if @socket_path
        Rails.logger.info "Connected to MPD via Unix socket at #{@socket_path}" if defined?(Rails)
      else
        Rails.logger.info "Connected to MPD at #{@host}:#{@port}" if defined?(Rails)
      end
      
      # Report initial volume
      report_volume
      
    rescue => e
      Rails.logger.error "Failed to connect to MPD: #{e.message}" if defined?(Rails)
      Rails.logger.error "Error class: #{e.class}" if defined?(Rails)
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}" if defined?(Rails)
      if @socket_path
        Rails.logger.error "Connection details: socket_path=#{@socket_path}" if defined?(Rails)
      else
        Rails.logger.error "Connection details: host=#{@host}, port=#{@port}" if defined?(Rails)
      end
      @connected = false
      raise
    end
  end

  def disconnect
    return unless @mpd && @connected
    
    begin
      @mpd.disconnect
      @connected = false
      Rails.logger.info "Disconnected from MPD" if defined?(Rails)
    rescue => e
      Rails.logger.error "Error disconnecting from MPD: #{e.message}" if defined?(Rails)
    end
  end

  def connected
    @connected
  end

  def connected?
    @connected
  end

  private

  def load_mpd_gem
    require 'mpd_client'
    Rails.logger.info "MPD client gem loaded successfully" if defined?(Rails)
  rescue LoadError => e
    Rails.logger.error "Failed to load MPD client gem: #{e.message}" if defined?(Rails)
    @mpd_available = false
  end

  def mpd_available?
    @mpd_available = defined?(MpdClient) unless defined?(@mpd_available)
    @mpd_available
  end

  def configure_mpd
    # Set up MPD configuration
    begin
      # Enable all tags for better metadata
      @mpd.tagtypes('all')
      
      # Set up idle mode for real-time updates
      @mpd.noidle
      
      Rails.logger.info "MPD configured successfully" if defined?(Rails)
    rescue => e
      Rails.logger.warn "Some MPD configuration failed: #{e.message}" if defined?(Rails)
    end
  end

  def report_volume
    begin
      volume = @mpd.status[:volume]
      Rails.logger.info "MPD initial volume: #{volume}%" if defined?(Rails)
    rescue => e
      Rails.logger.warn "Could not get initial volume: #{e.message}" if defined?(Rails)
    end
  end

  # =============================================================================
  # PLAYBACK CONTROL METHODS
  # =============================================================================

  def play(song_id = nil)
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      if song_id
        @mpd.playid(song_id)
        { success: true, message: "Playing song #{song_id}" }
      else
        @mpd.play
        { success: true, message: "Resumed playback" }
      end
    rescue => e
      { error: "Failed to play: #{e.message}" }
    end
  end

  def pause
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.pause
      { success: true, message: "Playback paused" }
    rescue => e
      { error: "Failed to pause: #{e.message}" }
    end
  end

  def stop
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.stop
      { success: true, message: "Playback stopped" }
    rescue => e
      { error: "Failed to stop: #{e.message}" }
    end
  end

  def next_song
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.next
      { success: true, message: "Next song" }
    rescue => e
      { error: "Failed to play next song: #{e.message}" }
    end
  end

  def previous_song
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.previous
      { success: true, message: "Previous song" }
    rescue => e
      { error: "Failed to play previous song: #{e.message}" }
    end
  end

  def resume
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.play
      { success: true, message: "Playback resumed" }
    rescue => e
      { error: "Failed to resume: #{e.message}" }
    end
  end

  # =============================================================================
  # STATUS AND INFORMATION METHODS
  # =============================================================================

  def get_status
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      status = @mpd.status
      @last_status = status
      
      {
        state: status[:state] || 'unknown',
        song: status[:song] || 0,
        songid: status[:songid] || 0,
        time: status[:time] || '0:0',
        elapsed: status[:elapsed] || 0,
        duration: status[:duration] || 0,
        bitrate: status[:bitrate] || 0,
        volume: status[:volume] || 0,
        repeat: status[:repeat] == '1',
        random: status[:random] == '1',
        single: status[:single] == '1',
        consume: status[:consume] == '1',
        playlist: status[:playlist] || 0,
        playlistlength: status[:playlistlength] || 0,
        mixrampdb: status[:mixrampdb] || 0,
        mixrampdelay: status[:mixrampdelay] || 0,
        audio: status[:audio] || '',
        nextsong: status[:nextsong] || 0,
        nextsongid: status[:nextsongid] || 0
      }
    rescue => e
      { error: "Failed to get status: #{e.message}" }
    end
  end

  def get_current_song
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      song = @mpd.currentsong
      return { error: 'No current song' } unless song
      
      {
        id: song[:id] || 0,
        pos: song[:pos] || 0,
        title: song[:title] || 'Unknown Title',
        artist: song[:artist] || 'Unknown Artist',
        album: song[:album] || 'Unknown Album',
        date: song[:date] || '',
        track: song[:track] || '',
        genre: song[:genre] || '',
        composer: song[:composer] || '',
        performer: song[:performer] || '',
        comment: song[:comment] || '',
        duration: song[:duration] || 0,
        file: song[:file] || ''
      }
    rescue => e
      { error: "Failed to get current song: #{e.message}" }
    end
  end

  def get_progress
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      status = @mpd.status
      elapsed = status[:elapsed] || 0
      duration = status[:duration] || 0
      
      if duration > 0
        progress = (elapsed.to_f / duration.to_f * 100).round(2)
      else
        progress = 0
      end
      
      {
        elapsed: elapsed,
        duration: duration,
        progress: progress,
        time: status[:time] || '0:0'
      }
    rescue => e
      { error: "Failed to get progress: #{e.message}" }
    end
  end

  def get_queue
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      playlist = @mpd.playlistinfo
      @last_queue_length = playlist.length
      
      songs = playlist.map do |song|
        {
          id: song[:id] || 0,
          pos: song[:pos] || 0,
          title: song[:title] || 'Unknown Title',
          artist: song[:artist] || 'Unknown Artist',
          album: song[:album] || 'Unknown Album',
          duration: song[:duration] || 0,
          file: song[:file] || ''
        }
      end
      
      {
        songs: songs,
        count: songs.length,
        total_duration: songs.sum { |s| s[:duration] || 0 }
      }
    rescue => e
      { error: "Failed to get queue: #{e.message}" }
    end
  end

  # =============================================================================
  # VOLUME CONTROL METHODS
  # =============================================================================

  def get_volume
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      status = @mpd.status
      volume = status[:volume] || 0
      
      {
        volume: volume,
        muted: volume == 0
      }
    rescue => e
      { error: "Failed to get volume: #{e.message}" }
    end
  end

  def set_volume(volume)
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      # Ensure volume is between 0 and 100
      volume = [[0, volume.to_i].max, 100].min
      
      @mpd.setvol(volume)
      
      {
        success: true,
        volume: volume,
        message: "Volume set to #{volume}%"
      }
    rescue => e
      { error: "Failed to set volume: #{e.message}" }
    end
  end

  def volume_up(amount = 5)
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      current_volume = @mpd.status[:volume] || 0
      new_volume = [[100, current_volume + amount].min, 0].max
      
      @mpd.setvol(new_volume)
      
      {
        success: true,
        volume: new_volume,
        message: "Volume increased to #{new_volume}%"
      }
    rescue => e
      { error: "Failed to increase volume: #{e.message}" }
    end
  end

  def volume_down(amount = 5)
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      current_volume = @mpd.status[:volume] || 0
      new_volume = [[100, current_volume - amount].min, 0].max
      
      @mpd.setvol(new_volume)
      
      {
        success: true,
        volume: new_volume,
        message: "Volume decreased to #{new_volume}%"
      }
    rescue => e
      { error: "Failed to decrease volume: #{e.message}" }
    end
  end

  # =============================================================================
  # QUEUE MANAGEMENT METHODS
  # =============================================================================

  def add_song(file_path)
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.add(file_path)
      
      # Get updated queue length
      status = @mpd.status
      new_length = status[:playlistlength] || 0
      
      {
        success: true,
        message: "Added #{file_path} to queue",
        queue_length: new_length
      }
    rescue => e
      { error: "Failed to add song: #{e.message}" }
    end
  end

  def remove_song(position)
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.delete(position)
      
      # Get updated queue length
      status = @mpd.status
      new_length = status[:playlistlength] || 0
      
      {
        success: true,
        message: "Removed song at position #{position}",
        queue_length: new_length
      }
    rescue => e
      { error: "Failed to remove song: #{e.message}" }
    end
  end

  def clear_queue
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      @mpd.clear
      
      {
        success: true,
        message: "Queue cleared",
        queue_length: 0
      }
    rescue => e
      { error: "Failed to clear queue: #{e.message}" }
    end
  end

  # =============================================================================
  # POLLING AND BACKGROUND PROCESSING
  # =============================================================================

  def start_polling
    return if @shutdown
    
    Thread.new do
      Rails.logger.info "Starting MPD polling thread" if defined?(Rails)
      
      while !@shutdown
        begin
          if connected?
            # Get current status
            status = get_status
            if status[:error]
              Rails.logger.warn "Error getting status: #{status[:error]}" if defined?(Rails)
            end
            
            # Get current song info
            song = get_current_song
            if song[:error]
              Rails.logger.warn "Error getting current song: #{song[:error]}" if defined?(Rails)
            end
            
            # Get queue info
            queue = get_queue
            if queue[:error]
              Rails.logger.warn "Error getting queue: #{queue[:error]}" if defined?(Rails)
            end
            
            # Store last known values
            @last_status = status unless status[:error]
            @last_queue_length = queue[:count] unless queue[:error]
            
            # Broadcast updates via ActionCable if available
            broadcast_updates(status, song, queue) if defined?(ActionCable)
          else
            # Try to reconnect
            attempt_reconnect
          end
          
          # Wait before next poll
          sleep 2
          
        rescue => e
          Rails.logger.error "Error in MPD polling thread: #{e.message}" if defined?(Rails)
          Rails.logger.error e.backtrace.first(3).join("\n") if defined?(Rails)
          sleep 5
        end
      end
      
      Rails.logger.info "MPD polling thread stopped" if defined?(Rails)
    end
  end

  def stop_polling
    @shutdown = true
    Rails.logger.info "Stopping MPD polling" if defined?(Rails)
  end

  def attempt_reconnect
    return if @reconnect_attempts >= @max_reconnect_attempts
    
    @reconnect_attempts += 1
    Rails.logger.info "Attempting MPD reconnection #{@reconnect_attempts}/#{@max_reconnect_attempts}" if defined?(Rails)
    
    begin
      disconnect if @mpd
      sleep @reconnect_delay
      connect
      
      if connected?
        @reconnect_attempts = 0
        Rails.logger.info "MPD reconnection successful" if defined?(Rails)
      else
        Rails.logger.warn "MPD reconnection failed" if defined?(Rails)
      end
    rescue => e
      Rails.logger.error "MPD reconnection error: #{e.message}" if defined?(Rails)
    end
  end

  def broadcast_updates(status, song, queue)
    # This method would broadcast updates via ActionCable
    # Implementation depends on your ActionCable setup
    # For now, just log the updates
    Rails.logger.debug "MPD status update: #{status[:state]}" if defined?(Rails)
  end

  # =============================================================================
  # UTILITY METHODS
  # =============================================================================

  def health_check
    return { status: 'disconnected', error: 'Not connected to MPD' } unless connected?
    
    begin
      # Try to get basic status
      status = @mpd.status
      
      {
        status: 'healthy',
        connected: true,
        state: status[:state] || 'unknown',
        volume: status[:volume] || 0,
        queue_length: status[:playlistlength] || 0
      }
    rescue => e
      {
        status: 'unhealthy',
        connected: false,
        error: e.message
      }
    end
  end

  def get_mpd_version
    return { error: 'Not connected to MPD' } unless connected?
    
    begin
      version = @mpd.version
      {
        version: version,
        message: "MPD version: #{version}"
      }
    rescue => e
      { error: "Failed to get MPD version: #{e.message}" }
    end
  end
end
