class PowerSyncService
  include Singleton
  
  def initialize
    @sync_lock = Mutex.new
  end
  
  # Start the sync process
  def start_sync
    Rails.logger.info "Starting PowerSync for archive..."
    
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
    set_sync_flag('stop', 'true')
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
      rsync_enabled: SystemSetting.rsync_enabled?,
      file_sync_enabled: SystemSetting.file_sync_enabled?,
      file_sync_in_progress: SystemSetting.file_sync_in_progress?,
      last_file_sync: SystemSetting.last_file_sync_time,
      file_sync_status: SystemSetting.file_sync_status
    }
  end
  
  # Force a sync now
  def force_sync
    Rails.logger.info "Forcing PowerSync..."
    perform_sync
  end

  # Force a file sync now
  def force_file_sync
    Rails.logger.info "Forcing file sync..."
    perform_file_sync
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
  
  # API endpoint for slave archives to fetch changes
  def get_changes_since(since_time)
    changes = []
    
    # Get changes from all relevant tables since the specified time
    changes.concat(get_song_changes_since(since_time))
    changes.concat(get_artist_changes_since(since_time))
    changes.concat(get_album_changes_since(since_time))
    changes.concat(get_genre_changes_since(since_time))
    changes.concat(get_playlist_changes_since(since_time))
    
    changes
  end
  
  # API endpoint for slave archives to apply changes
  def apply_changes_from_master(changes)
    Rails.logger.info "Applying #{changes.length} changes from master"
    
    changes.each do |change|
      apply_change(change)
    end
    
    Rails.logger.info "Successfully applied #{changes.length} changes"
  end
  
  private
  
  def initialize_sync
    Rails.logger.info "Initializing PowerSync..."
    
    # Create sync tables if they don't exist
    create_sync_tables
    
    # Set initial sync timestamp
    set_sync_flag('initialized', Time.current.to_s)
    set_sync_flag('count', '0')
    set_sync_flag('error_count', '0')
    
    Rails.logger.info "PowerSync initialized"
  end
  
  def create_sync_tables
    # This would create the sync tables if they don't exist
    # In a real implementation, this would use PowerSync's schema management
    Rails.logger.info "Sync tables ready"
  end
  
  def sync_loop
    loop do
      break if get_sync_flag('stop') == 'true'
      
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
        set_sync_flag('last_sync', Time.current.to_s)
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
    get_sync_flag("slave:#{slave_url}:last_sync")
  end
  
  def get_changes_since(since_time)
    # Get changes from local database since the specified time
    changes = []
    
    # Get changes from all relevant tables since the specified time
    changes.concat(get_song_changes_since(since_time))
    changes.concat(get_artist_changes_since(since_time))
    changes.concat(get_album_changes_since(since_time))
    changes.concat(get_genre_changes_since(since_time))
    changes.concat(get_playlist_changes_since(since_time))
    
    changes
  end
  
  def get_song_changes_since(since_time)
    # Get song changes since the specified time
    songs = Song.where('updated_at > ?', since_time) if since_time
    
    songs.map do |song|
      {
        type: 'song',
        action: 'update',
        id: song.id,
        data: song.attributes,
        timestamp: song.updated_at
      }
    end
  end
  
  def get_artist_changes_since(since_time)
    # Get artist changes since the specified time
    artists = Artist.where('updated_at > ?', since_time) if since_time
    
    artists.map do |artist|
      {
        type: 'artist',
        action: 'update',
        id: artist.id,
        data: artist.attributes,
        timestamp: artist.updated_at
      }
    end
  end
  
  def get_album_changes_since(since_time)
    # Get album changes since the specified time
    albums = Album.where('updated_at > ?', since_time) if since_time
    
    albums.map do |album|
      {
        type: 'album',
        action: 'update',
        id: album.id,
        data: album.attributes,
        timestamp: album.updated_at
      }
    end
  end
  
  def get_genre_changes_since(since_time)
    # Get genre changes since the specified time
    genres = Genre.where('updated_at > ?', since_time) if since_time
    
    genres.map do |genre|
      {
        type: 'genre',
        action: 'update',
        id: genre.id,
        data: genre.attributes,
        timestamp: genre.updated_at
      }
    end
  end
  
  def get_playlist_changes_since(since_time)
    # Get playlist changes since the specified time
    playlists = Playlist.where('updated_at > ?', since_time) if since_time
    
    playlists.map do |playlist|
      {
        type: 'playlist',
        action: 'update',
        id: playlist.id,
        data: playlist.attributes,
        timestamp: playlist.updated_at
      }
    end
  end
  
  def send_changes_to_slave(slave_url, changes)
    # Send changes to slave archive via API
    # For now, just log
    Rails.logger.debug "Sending #{changes.length} changes to #{slave_url}"
  end
  
  def update_last_sync_to_slave(slave_url)
    set_sync_flag("slave:#{slave_url}:last_sync", Time.current.to_s)
  end
  
  def update_sync_metadata(sync_type)
    set_sync_flag('last_sync', Time.current.to_s)
    set_sync_flag('last_type', sync_type)
    increment_sync_count
  end
  
  def sync_initialized?
    get_sync_flag('initialized').present?
  end
  
  def sync_running?
    get_sync_flag('stop') != 'true'
  end
  
  def last_sync_time
    timestamp = get_sync_flag('last_sync')
    timestamp ? Time.parse(timestamp) : nil
  end
  
  def sync_count
    get_sync_flag('count')&.to_i || 0
  end
  
  def error_count
    get_sync_flag('error_count')&.to_i || 0
  end
  
  def last_error
    get_sync_flag('last_error')
  end
  
  def increment_sync_count
    current_count = sync_count
    set_sync_flag('count', (current_count + 1).to_s)
  end
  
  def increment_error_count
    current_count = error_count
    set_sync_flag('error_count', (current_count + 1).to_s)
    set_sync_flag('last_error', Time.current.to_s)
  end

  # File sync methods
  def perform_file_sync
    return unless SystemSetting.file_sync_enabled?
    
    begin
      # Set sync in progress
      SystemSetting.set('file_sync_in_progress', 'true', 'File sync in progress flag')
      SystemSetting.set('file_sync_status', 'syncing', 'Current file sync status')
      
      case SystemSetting.archive_role
      when 'master'
        sync_files_to_slaves
      when 'slave'
        sync_files_from_master
      else
        Rails.logger.info "Standalone mode - no file sync needed"
      end
      
      # Update sync status
      SystemSetting.set('last_file_sync_time', Time.current.to_s, 'Last file sync timestamp')
      SystemSetting.set('file_sync_status', 'completed', 'Current file sync status')
      
    rescue => e
      Rails.logger.error "File sync failed: #{e.message}"
      SystemSetting.set('file_sync_status', 'failed', 'Current file sync status')
      raise e
    ensure
      # Clear sync in progress flag
      SystemSetting.set('file_sync_in_progress', 'false', 'File sync in progress flag')
    end
  end

  def sync_files_to_slaves
    Rails.logger.info "Syncing files to slaves..."
    
    script_path = Rails.root.join('scripts', 'sync_master_to_slaves.sh')
    return unless File.exist?(script_path)
    
    # Set environment variables for the script
    env = {
      'ARCHIVE_ROLE' => SystemSetting.archive_role,
      'FILE_SYNC_ENABLED' => SystemSetting.file_sync_enabled?.to_s,
      'MASTER_STORAGE_PATH' => SystemSetting.rsync_source_path,
      'SLAVE_HOSTS' => SystemSetting.slave_hosts.join(' '),
      'SLAVE_STORAGE_PATH' => SystemSetting.rsync_dest_path
    }
    
    # Run the sync script
    result = system(env, script_path.to_s)
    
    if result
      Rails.logger.info "File sync to slaves completed successfully"
    else
      raise "File sync to slaves failed"
    end
  end

  def sync_files_from_master
    Rails.logger.info "Syncing files from master..."
    
    script_path = Rails.root.join('scripts', 'sync_slave_from_master.sh')
    return unless File.exist?(script_path)
    
    # Set environment variables for the script
    env = {
      'ARCHIVE_ROLE' => SystemSetting.archive_role,
      'FILE_SYNC_ENABLED' => SystemSetting.file_sync_enabled?.to_s,
      'MASTER_HOST' => SystemSetting.master_host,
      'MASTER_STORAGE_PATH' => SystemSetting.rsync_source_path,
      'LOCAL_STORAGE_PATH' => SystemSetting.rsync_dest_path
    }
    
    # Run the sync script
    result = system(env, script_path.to_s)
    
    if result
      Rails.logger.info "File sync from master completed successfully"
    else
      raise "File sync from master failed"
    end
  end
  
  # Database-based sync flag storage
  def set_sync_flag(key, value)
    SystemSetting.set("sync_#{key}", value, "PowerSync internal flag: #{key}")
  end
  
  def get_sync_flag(key)
    SystemSetting.get("sync_#{key}")
  end

  # API-based sync methods for Phase 3
  def pull_changes_from_master(since_time = nil)
    return false unless SystemSetting.slave?
    return false unless SystemSetting.sync_enabled?
    
    master_url = SystemSetting.master_archive_url
    slave_key = SystemSetting.slave_key_encrypted
    node_id = SystemSetting.archive_node_id
    
    return false unless master_url.present? && slave_key.present? && node_id.present?
    
    # Decrypt the key
    key = SystemSetting.decrypt_value(slave_key)
    return false unless key.present?
    
    begin
      # Build request URL
      url = "#{master_url}/api/v1/sync/changes"
      url += "?since=#{since_time.iso8601}" if since_time
      
      # Make API request
      response = HTTP.headers(
        'X-Signature' => key,
        'X-Node-ID' => node_id,
        'Content-Type' => 'application/json'
      ).get(url)
      
      return false unless response.status.success?
      
      data = JSON.parse(response.body.to_s)
      master_changes = data['changes'] || []
      
      # Get local changes that might conflict
      local_changes = get_local_changes_since(since_time)
      
      # Resolve conflicts
      resolved_changes = resolve_conflicts_with_master(master_changes, local_changes)
      
      # Apply resolved changes
      applied_count = apply_resolved_changes(resolved_changes)
      
      Rails.logger.info "Pulled #{applied_count} changes from master archive (conflicts resolved: #{resolved_changes.count - master_changes.count})"
      set_sync_flag('last_sync', Time.current.to_s)
      increment_sync_count
      
      return true
      
    rescue => e
      Rails.logger.error "Failed to pull changes from master: #{e.message}"
      increment_error_count
      return false
    end
  end

  def push_changes_to_master
    return false unless SystemSetting.slave?
    return false unless SystemSetting.sync_enabled?
    
    master_url = SystemSetting.master_archive_url
    slave_key = SystemSetting.slave_key_encrypted
    node_id = SystemSetting.archive_node_id
    
    return false unless master_url.present? && slave_key.present? && node_id.present?
    
    # Decrypt the key
    key = SystemSetting.decrypt_value(slave_key)
    return false unless key.present?
    
    # Get local changes that haven't been sent to master
    local_changes = SyncChange.where(applied_to_slaves: [])
    return true if local_changes.empty?  # No changes to push
    
    begin
      # Format changes for API
      changes_data = local_changes.map do |change|
        {
          table: change.table_name,
          record_id: change.record_id,
          type: change.change_type,
          data: change.change_data
        }
      end
      
      # Make API request
      response = HTTP.headers(
        'X-Signature' => key,
        'X-Node-ID' => node_id,
        'Content-Type' => 'application/json'
      ).post("#{master_url}/api/v1/sync/apply", json: { changes: changes_data })
      
      return false unless response.status.success?
      
      data = JSON.parse(response.body.to_s)
      applied_count = data['applied_count'] || 0
      
      Rails.logger.info "Pushed #{applied_count} changes to master archive"
      set_sync_flag('last_sync', Time.current.to_s)
      increment_sync_count
      
      return true
      
    rescue => e
      Rails.logger.error "Failed to push changes to master: #{e.message}"
      increment_error_count
      return false
    end
  end

  # Initial sync for new slave archives
  def perform_initial_sync
    return false unless SystemSetting.slave?
    
    Rails.logger.info "Starting initial sync from master..."
    
    master_url = SystemSetting.master_archive_url
    slave_key = SystemSetting.slave_key_encrypted
    node_id = SystemSetting.archive_node_id
    
    return false unless master_url.present? && slave_key.present? && node_id.present?
    
    # Decrypt the key
    key = SystemSetting.decrypt_value(slave_key)
    return false unless key.present?
    
    begin
      # Get ALL data from master (not just recent changes)
      response = HTTP.headers(
        'X-Signature' => key,
        'X-Node-ID' => node_id,
        'Content-Type' => 'application/json'
      ).get("#{master_url}/api/v1/sync/initial_data")
      
      return false unless response.status.success?
      
      data = JSON.parse(response.body.to_s)
      
      # Clear existing data (optional - depends on requirements)
      clear_existing_data if data['clear_existing']
      
      # Apply all data from master
      applied_count = apply_initial_data(data)
      
      # Set initial sync timestamp
      set_sync_flag('initial_sync_completed', Time.current.to_s)
      set_sync_flag('last_sync', Time.current.to_s)
      
      Rails.logger.info "Initial sync completed: #{applied_count} records imported"
      return true
      
    rescue => e
      Rails.logger.error "Initial sync failed: #{e.message}"
      increment_error_count
      return false
    end
  end

  private

  def clear_existing_data
    Rails.logger.info "Clearing existing data for initial sync..."
    
    # Clear all data except system settings and sync metadata
    Song.delete_all
    Artist.delete_all
    Album.delete_all
    Genre.delete_all
    Playlist.delete_all
    
    # Clear sync changes
    SyncChange.delete_all
    
    Rails.logger.info "Existing data cleared"
  end

  def apply_initial_data(data)
    applied_count = 0
    
    # Apply data in dependency order
    ['genres', 'artists', 'albums', 'songs', 'playlists'].each do |table|
      records = data[table] || []
      Rails.logger.info "Applying #{records.count} #{table} from master..."
      
      records.each do |record_data|
        begin
          model_class = table.classify.constantize
          
          # Remove id to let Rails assign new one
          record_data = record_data.except('id', 'created_at', 'updated_at')
          
          record = model_class.create!(record_data)
          applied_count += 1
          
        rescue => e
          Rails.logger.error "Failed to create #{table.singularize}: #{e.message}"
        end
      end
    end
    
    applied_count
  end

  # Conflict resolution methods
  def get_local_changes_since(since_time)
    changes = SyncChange.since(since_time || 1.hour.ago)
    changes.map do |change|
      {
        'table' => change.table_name,
        'record_id' => change.record_id,
        'type' => change.change_type,
        'data' => change.change_data,
        'timestamp' => change.created_at.iso8601
      }
    end
  end

  def resolve_conflicts_with_master(master_changes, local_changes)
    conflict_service = ConflictResolutionService.instance
    resolved_changes = conflict_service.resolve_conflicts(master_changes, local_changes)
    
    # Convert resolved changes back to change data format
    resolved_changes.map do |resolution|
      resolution[:change]
    end
  end

  def apply_resolved_changes(resolved_changes)
    applied_count = 0
    
    resolved_changes.each do |change_data|
      begin
        change = SyncChange.create!(
          table_name: change_data['table'],
          record_id: change_data['record_id'],
          change_type: change_data['type'],
          change_data: change_data['data']
        )
        
        if change.apply_locally
          applied_count += 1
        end
        
      rescue => e
        Rails.logger.error "Failed to apply resolved change: #{e.message}"
      end
    end
    
    applied_count
  end
end 