class Api::V1::SyncController < ApplicationController
  include ApiAuthentication
  
  before_action :authenticate_slave_request, only: [:changes, :apply, :status]
  before_action :authenticate_jukebox_request, only: [:jukebox_status]
  
  # GET /api/v1/sync/changes?since=timestamp
  # Get changes since a specific timestamp
  def changes
    since_time = parse_timestamp(params[:since])
    
    changes = SyncChange.since(since_time)
                       .where.not(applied_to_slaves: [@current_slave.node_id])
                       .order(:created_at)
                       .limit(100)  # Limit to prevent overwhelming response
    
    render json: {
      changes: changes.map { |change| format_change(change) },
      count: changes.count,
      since: since_time,
      current_time: Time.current
    }
  end
  
  # POST /api/v1/sync/apply
  # Apply changes from slave to master
  def apply
    changes_data = params[:changes] || []
    
    if changes_data.empty?
      render json: { message: 'No changes to apply' }
      return
    end
    
    applied_count = 0
    errors = []
    
    changes_data.each do |change_data|
      begin
        change = SyncChange.create!(
          table_name: change_data[:table],
          record_id: change_data[:record_id],
          change_type: change_data[:type],
          change_data: change_data[:data]
        )
        
        # Mark as applied by this slave
        change.mark_applied_by_slave(@current_slave.node_id)
        applied_count += 1
        
      rescue => e
        errors << {
          change: change_data,
          error: e.message
        }
      end
    end
    
    render json: {
      applied_count: applied_count,
      error_count: errors.count,
      errors: errors
    }
  end
  
  # GET /api/v1/sync/status
  # Get sync status and health information
  def status
    render json: {
      archive_id: SystemSetting.archive_node_id,
      archive_role: SystemSetting.archive_role,
      sync_enabled: SystemSetting.sync_enabled?,
      file_sync_enabled: SystemSetting.file_sync_enabled?,
      last_sync: PowerSyncService.instance.sync_status[:last_sync],
      sync_count: PowerSyncService.instance.sync_status[:sync_count],
      error_count: PowerSyncService.instance.sync_status[:error_count],
      healthy: PowerSyncService.instance.healthy?,
      current_time: Time.current
    }
  end
  
  # GET /api/v1/sync/jukebox_status
  # Get jukebox-specific status
  def jukebox_status
    render json: {
      archive_id: SystemSetting.archive_node_id,
      archive_name: SystemSetting.site_name,
      jukebox_access: true,
      current_time: Time.current
    }
  end

  # GET /api/v1/sync/initial_data
  # Get all data for initial slave sync
  def initial_data
    render json: {
      clear_existing: true,  # Recommend clearing existing data
      genres: Genre.all.map(&:attributes),
      artists: Artist.all.map(&:attributes),
      albums: Album.all.map(&:attributes),
      songs: Song.all.map(&:attributes),
      playlists: Playlist.all.map(&:attributes),
      total_records: Genre.count + Artist.count + Album.count + Song.count + Playlist.count,
      exported_at: Time.current
    }
  end
  
  private
  
  def format_change(change)
    {
      id: change.id,
      table: change.table_name,
      record_id: change.record_id,
      type: change.change_type,
      data: change.change_data,
      timestamp: change.created_at
    }
  end
  
  def parse_timestamp(timestamp_param)
    return 1.hour.ago unless timestamp_param.present?
    
    begin
      Time.parse(timestamp_param)
    rescue ArgumentError
      1.hour.ago
    end
  end
end 