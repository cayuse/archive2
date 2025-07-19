class PowerSyncService
  include Singleton
  
  def initialize
    @redis = Redis.new(
      host: ENV.fetch('REDIS_HOST', 'localhost'),
      port: ENV.fetch('REDIS_PORT', 6379),
      db: ENV.fetch('REDIS_DB', 0)
    )
  end
  
  # Start the sync process
  def start_sync
    Rails.logger.info "Starting PowerSync with archive..."
    
    # Initialize sync if not already done
    initialize_sync unless sync_initialized?
    
    # Start background sync thread
    Thread.new do
      sync_loop
    end
    
    Rails.logger.info "PowerSync started successfully"
  end
  
  # Stop the sync process
  def stop_sync
    @redis.set('jukebox:sync:stop', 'true')
    Rails.logger.info "PowerSync stop requested"
  end
  
  # Get sync status
  def sync_status
    {
      initialized: sync_initialized?,
      last_sync: last_sync_time,
      sync_count: sync_count,
      error_count: error_count,
      last_error: last_error,
      running: sync_running?
    }
  end
  
  # Force a sync now
  def force_sync
    Rails.logger.info "Forcing PowerSync..."
    perform_sync
  end
  
  # Check if sync is healthy
  def healthy?
    return false unless sync_initialized?
    return false if error_count > 10
    
    # Check if last sync was recent
    last_sync = last_sync_time
    return false if last_sync.nil?
    
    # Sync should happen at least every 5 minutes
    Time.current - last_sync < 5.minutes
  end
  
  private
  
  def initialize_sync
    Rails.logger.info "Initializing PowerSync..."
    
    # Create sync tables if they don't exist
    create_sync_tables
    
    # Set initial sync timestamp
    @redis.set('jukebox:sync:initialized', Time.current.to_s)
    @redis.set('jukebox:sync:count', 0)
    @redis.set('jukebox:sync:error_count', 0)
    
    Rails.logger.info "PowerSync initialized"
  end
  
  def create_sync_tables
    # This would create the sync tables if they don't exist
    # In a real implementation, this would use PowerSync's schema management
    Rails.logger.info "Sync tables ready"
  end
  
  def sync_loop
    loop do
      break if @redis.get('jukebox:sync:stop') == 'true'
      
      begin
        perform_sync
        sleep 30  # Default sync interval
      rescue => e
        Rails.logger.error "PowerSync error: #{e.message}"
        increment_error_count
        sleep 30 # Wait longer on error
      end
    end
  end
  
  def perform_sync
    Rails.logger.debug "Performing PowerSync..."
    
    # In a real implementation, this would use PowerSync's sync API
    # For now, we'll simulate the sync process
    
    # Update sync timestamp
    @redis.set('jukebox:last_sync', Time.current.to_s)
    increment_sync_count
    
    Rails.logger.debug "PowerSync completed"
  end
  
  def sync_initialized?
    @redis.exists('jukebox:sync:initialized')
  end
  
  def sync_running?
    @redis.get('jukebox:sync:stop') != 'true'
  end
  
  def last_sync_time
    timestamp = @redis.get('jukebox:last_sync')
    timestamp ? Time.parse(timestamp) : nil
  end
  
  def sync_count
    @redis.get('jukebox:sync:count')&.to_i || 0
  end
  
  def error_count
    @redis.get('jukebox:sync:error_count')&.to_i || 0
  end
  
  def last_error
    @redis.get('jukebox:sync:last_error')
  end
  
  def increment_sync_count
    @redis.incr('jukebox:sync:count')
  end
  
  def increment_error_count
    @redis.incr('jukebox:sync:error_count')
    @redis.set('jukebox:sync:last_error', Time.current.to_s)
  end
end 