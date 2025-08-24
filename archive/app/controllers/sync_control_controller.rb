class SyncControlController < ApplicationController
  before_action :require_admin
  
  # GET /sync_control/status
  def status
    @sync_status = FailSafeSyncService.instance.sync_status
    @system_settings = {
      sync_enabled: SystemSetting.sync_enabled?,
      sync_paused: SystemSetting.sync_paused?,
      sync_emergency_stop: SystemSetting.sync_emergency_stop?,
      sync_health_check_enabled: SystemSetting.sync_health_check_enabled?,
      sync_max_concurrent_operations: SystemSetting.sync_max_concurrent_operations,
      sync_operation_timeout: SystemSetting.sync_operation_timeout,
      sync_interval: SystemSetting.sync_interval,
      archive_role: SystemSetting.archive_role,
      master_archive_url: SystemSetting.master_archive_url
    }
    
    @recent_sync_attempts = SyncStatusTracking.order(:last_attempt_at).limit(20)
    @failed_syncs = SyncStatusTracking.recent_failures.limit(10)
    
    render 'sync_control/status'
  end
  
  # POST /sync_control/pause
  def pause_sync
    SystemSetting.pause_sync
    FailSafeSyncService.instance.stop_sync
    
    flash[:success] = "Sync has been paused. The system will continue to function normally without syncing."
    redirect_to sync_control_status_path
  end
  
  # POST /sync_control/resume
  def resume_sync
    SystemSetting.resume_sync
    SystemSetting.clear_emergency_stop
    FailSafeSyncService.instance.start_sync
    
    flash[:success] = "Sync has been resumed."
    redirect_to sync_control_status_path
  end
  
  # POST /sync_control/emergency_stop
  def emergency_stop
    SystemSetting.emergency_stop_sync
    FailSafeSyncService.instance.stop_sync
    
    flash[:warning] = "Sync has been emergency stopped due to system issues. Manual intervention required."
    redirect_to sync_control_status_path
  end
  
  # POST /sync_control/clear_emergency_stop
  def clear_emergency_stop
    SystemSetting.clear_emergency_stop
    
    flash[:success] = "Emergency stop has been cleared. Sync can now be resumed."
    redirect_to sync_control_status_path
  end
  
  # POST /sync_control/force_sync
  def force_sync
    result = FailSafeSyncService.instance.force_sync
    
    if result[:status] == 'queued'
      flash[:success] = "Manual sync has been queued for background execution."
    else
      flash[:error] = "Failed to queue sync: #{result[:message]}"
    end
    
    redirect_to sync_control_status_path
  end
  
  # POST /sync_control/update_settings
  def update_settings
    begin
      # Update sync control settings
      if params[:sync_health_check_enabled].present?
        SystemSetting.set('sync_health_check_enabled', params[:sync_health_check_enabled] == '1')
      end
      
      if params[:sync_max_concurrent_operations].present?
        SystemSetting.set('sync_max_concurrent_operations', params[:sync_max_concurrent_operations])
      end
      
      if params[:sync_interval].present?
        SystemSetting.set('sync_interval', params[:sync_interval])
      end
      
      if params[:sync_operation_timeout].present?
        SystemSetting.set('sync_operation_timeout', params[:sync_operation_timeout])
      end
      
      flash[:success] = "Sync control settings updated successfully."
      
    rescue => e
      flash[:error] = "Failed to update settings: #{e.message}"
    end
    
    redirect_to sync_control_status_path
  end
  
  # POST /sync_control/clear_failed_syncs
  def clear_failed_syncs
    count = SyncStatusTracking.where(status: 'failed').count
    SyncStatusTracking.where(status: 'failed').update_all(
      status: 'success',
      error_message: nil,
      next_attempt_at: nil
    )
    
    flash[:success] = "Cleared #{count} failed sync records."
    redirect_to sync_control_status_path
  end
  
  private
  
  def require_admin
    unless current_user&.admin?
      flash[:error] = "Access denied. Admin privileges required."
      redirect_to root_path
    end
  end
end
