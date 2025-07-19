class PowerSyncService
  include Singleton
  
  def initialize
    @redis = Redis.new(
      host: ENV.fetch('REDIS_HOST', 'localhost'),
      port: ENV.fetch('REDIS_PORT', 6379),
      db: ENV.fetch('REDIS_DB', 0)
    )
    @sync_lock = Mutex.new
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
      running: sync_running?,
      archive_role: SystemSetting.archive_role,
      master_url: SystemSetting.master_archive_url,
      node_id: SystemSetting.archive_node_id,
      sync_enabled: SystemSetting.sync_enabled?,
      rsync_enabled: SystemSetting.rsync_enabled?
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
  
  # Archive-to-archive sync methods
  def sync_with_master
    return unless SystemSetting.slave?
    return if SystemSetting.master_archive_url.blank?
    
    Rails.logger.info "Syncing with master archive: #{SystemSetting.master_archive_url}"
    
    begin
      # Sync database changes
      sync_database_with_master
      
      # Sync files if enabled
      sync_files_with_master if SystemSetting.rsync_enabled?
      
      # Update sync metadata
      update_sync_metadata('master_sync')
      
    rescue => e
      Rails.logger.error "Master sync failed: #{e.message}"
      increment_error_count
      raise e
    end
  end
  
  def sync_to_slaves
    return unless SystemSetting.master?
    
    Rails.logger.info "Syncing to slave archives..."
    
    # Get list of slave archives (this would be configured)
    slave_archives = get_slave_archives
    
    slave_archives.each do |slave_url|
      begin
        sync_to_slave(slave_url)
      rescue => e
        Rails.logger.error "Failed to sync to slave #{slave_url}: #{e.message}"
        increment_error_count
      end
    end
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
        sleep SystemSetting.sync_interval
      rescue => e
        Rails.logger.error "PowerSync error: #{e.message}"
        increment_error_count
        sleep 30 # Wait longer on error
      end
    end
  end
  
  def perform_sync
    Rails.logger.debug "Performing PowerSync..."
    
    @sync_lock.synchronize do
      # Handle different archive roles
      case SystemSetting.archive_role
      when 'master'
        sync_to_slaves
      when 'slave'
        sync_with_master
      else
        # Standalone - just update sync timestamp
        @redis.set('jukebox:last_sync', Time.current.to_s)
        increment_sync_count
      end
    end
    
    Rails.logger.debug "PowerSync completed"
  end
  
  def sync_database_with_master
    master_url = SystemSetting.master_archive_url
    return if master_url.blank?
    
    # Get last sync timestamp
    last_sync = last_sync_time
    
    # Fetch changes from master since last sync
    changes = fetch_changes_from_master(master_url, last_sync)
    
    # Apply changes to local database
    apply_changes_to_local(changes)
    
    Rails.logger.info "Database sync completed with #{changes.length} changes"
  end
  
  def sync_files_with_master
    master_url = SystemSetting.master_archive_url
    return if master_url.blank?
    
    # Use rsync to sync files from master
    rsync_from_master(master_url)
    
    Rails.logger.info "File sync completed"
  end
  
  def sync_to_slave(slave_url)
    Rails.logger.info "Syncing to slave: #{slave_url}"
    
    # Get changes since last sync to this slave
    last_sync = get_last_sync_to_slave(slave_url)
    changes = get_changes_since(last_sync)
    
    # Send changes to slave
    send_changes_to_slave(slave_url, changes)
    
    # Update last sync timestamp for this slave
    update_last_sync_to_slave(slave_url)
    
    Rails.logger.info "Sync to slave #{slave_url} completed"
  end
  
  def fetch_changes_from_master(master_url, since_time)
    # This would make an API call to the master archive
    # to get changes since the specified time
    # For now, return empty array
    []
  end
  
  def apply_changes_to_local(changes)
    # Apply the changes to the local database
    # This would handle conflicts and apply changes atomically
    changes.each do |change|
      apply_change(change)
    end
  end
  
  def apply_change(change)
    # Apply a single change to the local database
    # This would handle different types of changes (create, update, delete)
    Rails.logger.debug "Applying change: #{change}"
  end
  
  def rsync_from_master(master_url)
    # Use rsync to sync files from master
    source_path = "#{master_url}:#{SystemSetting.rsync_source_path}"
    dest_path = SystemSetting.rsync_dest_path.presence || Rails.root.join('storage').to_s
    
    # Run rsync command
    system("rsync", "-avz", "--delete", source_path, dest_path)
  end
  
  def get_slave_archives
    # This would return a list of slave archive URLs
    # For now, return empty array
    []
  end
  
  def get_last_sync_to_slave(slave_url)
    @redis.get("jukebox:sync:slave:#{slave_url}:last_sync")
  end
  
  def get_changes_since(since_time)
    # Get changes from local database since the specified time
    # For now, return empty array
    []
  end
  
  def send_changes_to_slave(slave_url, changes)
    # Send changes to slave archive via API
    # For now, just log
    Rails.logger.debug "Sending #{changes.length} changes to #{slave_url}"
  end
  
  def update_last_sync_to_slave(slave_url)
    @redis.set("jukebox:sync:slave:#{slave_url}:last_sync", Time.current.to_s)
  end
  
  def update_sync_metadata(sync_type)
    @redis.set('jukebox:last_sync', Time.current.to_s)
    @redis.set("jukebox:sync:last_type", sync_type)
    increment_sync_count
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