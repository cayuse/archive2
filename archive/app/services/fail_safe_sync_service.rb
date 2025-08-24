class FailSafeSyncService
  include Singleton
  
  # Configuration constants
  SYNC_TIMEOUT = 30.seconds        # Maximum time any sync operation can take
  MAX_RETRIES = 3                  # Maximum retry attempts before giving up
  CIRCUIT_BREAKER_THRESHOLD = 5    # Failures before opening circuit breaker
  CIRCUIT_BREAKER_TIMEOUT = 5.minutes  # How long to keep circuit open
  
  def initialize
    @sync_threads = {}
    @circuit_breaker = {}
    @sync_lock = Mutex.new
    @running = false
  end
  
  # Start the fail-safe sync service
  def start_sync
    return if @running
    
    @sync_lock.synchronize do
      return if @running
      @running = true
      
      Rails.logger.info "Starting FailSafeSyncService..."
      
      # Start sync in background thread
      start_background_sync_thread
      
      Rails.logger.info "FailSafeSyncService started successfully"
    end
  end
  
  # Stop the sync service
  def stop_sync
    @sync_lock.synchronize do
      return unless @running
      @running = false
      
      Rails.logger.info "Stopping FailSafeSyncService..."
      
      # Stop all sync threads
      @sync_threads.values.each(&:exit)
      @sync_threads.clear
      
      Rails.logger.info "FailSafeSyncService stopped"
    end
  end
  
  # Force a sync operation (non-blocking)
  def force_sync
    return unless @running
    
    # Queue sync in background thread
    Thread.new do
      perform_sync_with_timeout
    end
    
    { status: 'queued', message: 'Sync queued for background execution' }
  end
  
  # Get sync status
  def sync_status
    {
      running: @running,
      threads: @sync_threads.count,
      circuit_breakers: @circuit_breaker,
      last_sync: get_last_sync_status,
      pending_retries: SyncStatusTracking.pending_retries.count,
      recent_failures: SyncStatusTracking.recent_failures.count
    }
  end
  
  # Check if sync is healthy
  def healthy?
    return false unless @running
    
    # Check if we have recent successful syncs
    recent_syncs = SyncStatusTracking.where('last_success_at > ?', 1.hour.ago)
    recent_syncs.any?
  end
  
  private
  
  def start_background_sync_thread
    @sync_threads[:main] = Thread.new do
      Thread.current.abort_on_exception = false
      
      loop do
        break unless @running
        
        begin
          # Check if sync is enabled and not paused
          next unless SystemSetting.sync_enabled?
          next if SystemSetting.sync_paused?
          next if SystemSetting.sync_emergency_stop?
          
          # Check circuit breaker
          next if circuit_breaker_open?
          
          # CLIENT-INITIATED SYNC: Only slaves initiate sync requests
          if SystemSetting.slave?
            perform_client_initiated_sync
          elsif SystemSetting.master?
            # Master just waits for client requests - no active syncing
            Rails.logger.debug "Master mode - waiting for client sync requests"
          else
            # Standalone - just update status
            update_sync_status('standalone', 'success')
          end
          
          # Wait for next sync interval
          sleep SystemSetting.sync_interval
          
        rescue => e
          Rails.logger.error "FailSafeSyncService error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          
          # Mark circuit breaker failure
          record_circuit_breaker_failure
          
          # Wait before retry
          sleep 30.seconds
        end
      end
    end
  end
  
  def perform_client_initiated_sync
    # CLIENT-INITIATED SYNC: Client connects to master and initiates sync
    Rails.logger.info "Initiating client sync with master..."
    
    tracking = SyncStatusTracking.find_or_create_by(
      sync_type: 'database',
      target_node_id: 'master'
    )
    
    tracking.mark_in_progress!
    
    begin
      # Use Timeout to ensure sync never hangs
      Timeout::timeout(SYNC_TIMEOUT) do
        # Step 1: Pull changes from master
        pull_changes_from_master
        
        # Step 2: Push local changes to master
        push_changes_to_master
      end
      
      tracking.mark_successful!
      Rails.logger.info "Client sync completed successfully"
      
    rescue Timeout::Error
      error_msg = "Client sync timed out after #{SYNC_TIMEOUT} seconds"
      Rails.logger.error error_msg
      tracking.mark_failed!(error_msg)
      
    rescue => e
      error_msg = "Client sync failed: #{e.message}"
      Rails.logger.error error_msg
      tracking.mark_failed!(error_msg)
    end
  end

  def perform_sync_with_timeout
    # Use Timeout to ensure sync never hangs
    Timeout::timeout(SYNC_TIMEOUT) do
      case SystemSetting.archive_role
      when 'master'
        # Master doesn't actively sync - just waits for client requests
        Rails.logger.debug "Master mode - no active syncing needed"
      when 'slave'
        perform_client_initiated_sync
      else
        # Standalone - just update status
        update_sync_status('standalone', 'success')
      end
    end
    
  rescue Timeout::Error
    Rails.logger.error "Sync operation timed out after #{SYNC_TIMEOUT} seconds"
    update_sync_status('timeout', 'failed', 'Operation timed out')
    
  rescue => e
    Rails.logger.error "Sync operation failed: #{e.message}"
    update_sync_status('error', 'failed', e.message)
  end
  
  def sync_to_slaves_safely
    return unless SystemSetting.master?
    
    # Get list of slave archives
    slave_archives = get_slave_archives
    
    slave_archives.each do |slave_url|
      Thread.new do
        sync_to_single_slave_safely(slave_url)
      end
    end
  end
  
  def sync_to_single_slave_safely(slave_url)
    tracking = SyncStatusTracking.find_or_create_by(
      sync_type: 'database',
      target_node_id: extract_node_id(slave_url)
    )
    
    tracking.mark_in_progress!
    
    begin
      # Perform sync with timeout
      Timeout::timeout(15.seconds) do
        sync_to_slave(slave_url)
      end
      
      tracking.mark_successful!
      
    rescue => e
      tracking.mark_failed!(e.message)
      Rails.logger.error "Failed to sync to slave #{slave_url}: #{e.message}"
    end
  end
  
  def sync_with_master_safely
    return unless SystemSetting.slave?
    
    tracking = SyncStatusTracking.find_or_create_by(
      sync_type: 'database',
      target_node_id: 'master'
    )
    
    tracking.mark_in_progress!
    
    begin
      # Perform sync with timeout
      Timeout::timeout(15.seconds) do
        sync_with_master
      end
      
      tracking.mark_successful!
      
    rescue => e
      tracking.mark_failed!(e.message)
      Rails.logger.error "Failed to sync with master: #{e.message}"
    end
  end
  
  def sync_to_slave(slave_url)
    # This would be the actual sync logic
    # For now, just simulate a sync operation
    Rails.logger.info "Syncing to slave: #{slave_url}"
    sleep 1 # Simulate work
  end
  
  def pull_changes_from_master
    # CLIENT: Pull changes from master via API
    master_url = SystemSetting.master_archive_url
    slave_key = get_slave_key
    node_id = SystemSetting.archive_node_id
    
    return false unless master_url.present? && slave_key.present? && node_id.present?
    
    Rails.logger.info "Pulling changes from master: #{master_url}"
    
    begin
      # Get last successful sync time
      last_sync = get_last_sync_time
      
      # Build request URL
      url = "#{master_url}/api/v1/sync/changes"
      url += "?since=#{last_sync.iso8601}" if last_sync
      
      # Make API request with timeout
      response = make_sync_request(:get, url, slave_key, node_id)
      return false unless response
      
      # Parse response
      data = JSON.parse(response.body.to_s)
      master_changes = data['changes'] || []
      
      Rails.logger.info "Received #{master_changes.length} changes from master"
      
      # Apply changes to local database
      apply_master_changes(master_changes)
      
      return true
      
    rescue => e
      Rails.logger.error "Failed to pull changes from master: #{e.message}"
      raise e
    end
  end
  
  def push_changes_to_master
    # CLIENT: Push local changes to master via API
    master_url = SystemSetting.master_archive_url
    slave_key = get_slave_key
    node_id = SystemSetting.archive_node_id
    
    return false unless master_url.present? && slave_key.present? && node_id.present?
    
    Rails.logger.info "Pushing changes to master: #{master_url}"
    
    begin
      # Get local changes that haven't been sent to master
      local_changes = get_local_changes_for_master
      return true if local_changes.empty?  # No changes to push
      
      Rails.logger.info "Pushing #{local_changes.length} local changes to master"
      
      # Make API request
      response = make_sync_request(:post, "#{master_url}/api/v1/sync/apply", slave_key, node_id, 
                                 json: { changes: local_changes })
      return false unless response
      
      # Parse response
      data = JSON.parse(response.body.to_s)
      applied_count = data['applied_count'] || 0
      
      Rails.logger.info "Successfully pushed #{applied_count} changes to master"
      
      # Mark changes as sent to master
      mark_changes_as_sent_to_master(local_changes)
      
      return true
      
    rescue => e
      Rails.logger.error "Failed to push changes to master: #{e.message}"
      raise e
    end
  end
  
  def sync_with_master
    # Legacy method - now calls client-initiated sync
    perform_client_initiated_sync
  end
  
  def get_slave_archives
    # This would return configured slave URLs
    # For now, return empty array
    []
  end
  
  def extract_node_id(url)
    # Extract node ID from URL for tracking
    URI(url).host
  rescue
    'unknown'
  end
  
  def circuit_breaker_open?
    # Check if circuit breaker is open for this operation
    failures = @circuit_breaker[:failures] || 0
    last_failure = @circuit_breaker[:last_failure]
    
    if failures >= CIRCUIT_BREAKER_THRESHOLD && last_failure
      # Check if enough time has passed to try again
      if Time.current - last_failure < CIRCUIT_BREAKER_TIMEOUT
        Rails.logger.warn "Circuit breaker is open, skipping sync"
        return true
      else
        # Reset circuit breaker
        @circuit_breaker.clear
      end
    end
    
    false
  end
  
  def record_circuit_breaker_failure
    @circuit_breaker[:failures] = (@circuit_breaker[:failures] || 0) + 1
    @circuit_breaker[:last_failure] = Time.current
  end
  
  def update_sync_status(sync_type, status, error_message = nil)
    tracking = SyncStatusTracking.find_or_create_by(
      sync_type: 'database',
      target_node_id: 'system'
    )
    
    case status
    when 'success'
      tracking.mark_successful!
    when 'failed'
      tracking.mark_failed!(error_message)
    end
  end
  
  def get_last_sync_status
    tracking = SyncStatusTracking.by_type('database').order(:last_success_at).last
    return nil unless tracking
    
    {
      last_success: tracking.last_success_at,
      last_attempt: tracking.last_attempt_at,
      status: tracking.status,
      error: tracking.error_message
    }
  end
  
  private
  
  def make_sync_request(method, url, slave_key, node_id, options = {})
    require 'net/http'
    require 'uri'
    
    uri = URI(url)
    
    # Set up HTTP client with timeouts
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10  # 10 second connection timeout
    http.read_timeout = 20  # 20 second read timeout
    
    # Build request
    case method
    when :get
      request = Net::HTTP::Get.new(uri)
    when :post
      request = Net::HTTP::Post.new(uri)
      request.body = options[:json].to_json if options[:json]
      request['Content-Type'] = 'application/json'
    end
    
    # Add authentication headers
    request['X-Signature'] = slave_key
    request['X-Node-ID'] = node_id
    
    # Make request
    response = http.request(request)
    
    # Check response
    if response.code.to_i >= 200 && response.code.to_i < 300
      return response
    else
      Rails.logger.error "Master API request failed: HTTP #{response.code} - #{response.body}"
      return nil
    end
    
  rescue => e
    Rails.logger.error "Network error during sync request: #{e.message}"
    return nil
  end
  
  def get_slave_key
    # Get the slave key for this node
    # This would be stored securely in the system settings
    SystemSetting.get('slave_key_encrypted')
  end
  
  def get_last_sync_time
    # Get the timestamp of the last successful sync
    tracking = SyncStatusTracking.by_type('database').by_target('master').where(status: 'success').order(:last_success_at).last
    tracking&.last_success_at
  end
  
  def get_local_changes_for_master
    # Get local changes that haven't been sent to master
    # This would query the SyncChange table for local changes
    []
  end
  
  def apply_master_changes(changes)
    # Apply changes received from master to local database
    # This would use the existing SyncChange model
    changes.each do |change_data|
      # Apply the change locally
      # Implementation depends on your change format
    end
  end
  
  def mark_changes_as_sent_to_master(changes)
    # Mark local changes as successfully sent to master
    # This would update the SyncChange records
  end
end
