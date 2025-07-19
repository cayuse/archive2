class ArchiveSyncController < ApplicationController
  before_action :require_admin
  
  def index
    @sync_status = PowerSyncService.instance.sync_status
    @system_settings = {
      archive_role: SystemSetting.archive_role,
      master_archive_url: SystemSetting.master_archive_url,
      archive_node_id: SystemSetting.archive_node_id,
      sync_enabled: SystemSetting.sync_enabled?,
      sync_interval: SystemSetting.sync_interval,
      rsync_enabled: SystemSetting.rsync_enabled?,
      rsync_source_path: SystemSetting.rsync_source_path,
      rsync_dest_path: SystemSetting.rsync_dest_path
    }
  end
  
  def update
    begin
      # Update archive role
      if params[:archive_role].present?
        SystemSetting.set('archive_role', params[:archive_role], 'Archive role: standalone, master, or slave')
      end
      
      # Update master archive URL
      if params[:master_archive_url].present?
        SystemSetting.set('master_archive_url', params[:master_archive_url], 'URL of master archive (for slave nodes)')
      end
      
      # Update archive node ID
      if params[:archive_node_id].present?
        SystemSetting.set('archive_node_id', params[:archive_node_id], 'Unique identifier for this archive node')
      end
      
      # Update sync settings
      SystemSetting.set('sync_enabled', params[:sync_enabled] == '1', 'Enable archive-to-archive synchronization')
      SystemSetting.set('sync_interval', params[:sync_interval], 'Sync interval in seconds')
      SystemSetting.set('rsync_enabled', params[:rsync_enabled] == '1', 'Enable rsync file synchronization')
      
      # Update rsync paths
      if params[:rsync_source_path].present?
        SystemSetting.set('rsync_source_path', params[:rsync_source_path], 'Source path for rsync')
      end
      
      if params[:rsync_dest_path].present?
        SystemSetting.set('rsync_dest_path', params[:rsync_dest_path], 'Destination path for rsync')
      end
      
      # Restart PowerSync if settings changed
      if sync_settings_changed?
        PowerSyncService.instance.stop_sync
        sleep 1
        PowerSyncService.instance.start_sync
      end
      
      flash[:success] = "Archive sync settings updated successfully"
      
    rescue => e
      flash[:error] = "Failed to update settings: #{e.message}"
    end
    
    redirect_to archive_sync_index_path
  end
  
  def test_connection
    master_url = params[:master_url] || SystemSetting.master_archive_url
    
    if master_url.blank?
      render json: { success: false, error: "Master URL is required" }
      return
    end
    
    begin
      # Test connection to master archive
      response = test_master_connection(master_url)
      
      if response[:success]
        render json: { success: true, message: "Connection successful", details: response[:details] }
      else
        render json: { success: false, error: response[:error] }
      end
      
    rescue => e
      render json: { success: false, error: "Connection failed: #{e.message}" }
    end
  end
  
  def force_sync
    begin
      PowerSyncService.instance.force_sync
      flash[:success] = "Manual sync initiated"
    rescue => e
      flash[:error] = "Sync failed: #{e.message}"
    end
    
    redirect_to archive_sync_index_path
  end
  
  private
  
  def sync_settings_changed?
    # Check if any sync-related settings have changed
    # This is a simplified check - in a real implementation you'd track changes more carefully
    true
  end
  
  def test_master_connection(master_url)
    require 'net/http'
    require 'uri'
    
    # Test basic connectivity
    uri = URI("#{master_url}/api/v1/health")
    
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 10) do |http|
      request = Net::HTTP::Get.new(uri)
      
      # Add authentication if configured
      if ENV['ARCHIVE_API_KEY']
        request['Authorization'] = "Bearer #{ENV['ARCHIVE_API_KEY']}"
      end
      
      response = http.request(request)
      
      if response.code == '200'
        {
          success: true,
          details: {
            status_code: response.code,
            content_type: response.content_type,
            body: response.body[0..200] # First 200 chars
          }
        }
      else
        {
          success: false,
          error: "HTTP #{response.code}: #{response.message}"
        }
      end
    end
    
  rescue => e
    {
      success: false,
      error: e.message
    }
  end
end 