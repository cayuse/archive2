class SettingsController < ApplicationController
  before_action :require_admin
  before_action :set_current_tab

  def show
    # Show the main settings page with navigation
    @current_tab = 'index'
  end

  def api_keys
    # Stub for API keys management
  end

  def song_types
    # Stub for song types management
  end

  # Theme management methods
  def themes
    @themes = Theme.all.order(:name)
    render 'settings/themes/index'
  end

  def show_theme
    @theme = Theme.find(params[:id])
    render 'settings/themes/show'
  end

  def new_theme
    @theme = Theme.new
    render 'settings/themes/new'
  end

  def edit_theme
    @theme = Theme.find(params[:id])
    render 'settings/themes/edit'
  end

  def create_theme
    @theme = Theme.new(theme_params)
    
    if @theme.save
      redirect_to manage_theme_settings_path(@theme), notice: 'Theme was successfully created.'
    else
      render 'settings/themes/new', status: :unprocessable_entity
    end
  end



  def update_theme
    @theme = Theme.find(params[:id])
    if @theme.update(theme_params)
      redirect_to manage_theme_settings_path(@theme), notice: 'Theme was successfully updated.'
    else
      render 'settings/themes/edit', status: :unprocessable_entity
    end
  end

  def destroy_theme
    @theme = Theme.find(params[:id])
    if @theme.is_default
      redirect_to manage_themes_settings_path, alert: 'Cannot delete the default theme.'
    else
      @theme.destroy
      redirect_to manage_themes_settings_path, notice: 'Theme was successfully deleted.'
    end
  end

  def duplicate_theme
    @theme = Theme.find(params[:id])
    new_theme = @theme.duplicate!
    if new_theme
      redirect_to manage_theme_settings_path(new_theme), notice: 'Theme was successfully duplicated.'
    else
      redirect_to manage_theme_settings_path(@theme), alert: 'Failed to duplicate theme.'
    end
  end

  def export_theme
    @theme = Theme.find(params[:id])
    # Export theme to filesystem (simplified)
    theme_dir = Rails.root.join('app', 'assets', 'stylesheets', 'themes', @theme.name)
    FileUtils.mkdir_p(theme_dir)
    
    # Export CSS
    css_file = theme_dir.join('theme.css')
    File.write(css_file, @theme.generate_css)
    
    # Export assets
    assets_dir = theme_dir.join('assets')
    FileUtils.mkdir_p(assets_dir)
    
    @theme.theme_assets.each do |asset|
      asset_dir = assets_dir.join(asset.asset_type.pluralize)
      FileUtils.mkdir_p(asset_dir)
      File.write(asset_dir.join(asset.filename), asset.file_data)
    end
    
    redirect_to manage_theme_settings_path(@theme), notice: "Theme exported to #{theme_dir}"
  end

  def switch_theme
    theme = Theme.find(params[:id])
    if theme
      # Deactivate all other themes
      Theme.update_all(is_active: false)
      # Activate the selected theme
      theme.update(is_active: true)
      redirect_to manage_themes_settings_path, notice: "Theme '#{theme.display_name}' is now active"
    else
      redirect_to manage_themes_settings_path, alert: "Theme not found"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to manage_themes_settings_path, alert: "Theme not found"
  end

  def preview_theme
    @theme = Theme.find(params[:id])
    render layout: 'preview'
  rescue ActiveRecord::RecordNotFound
    @theme = Theme.current
    render layout: 'preview'
  end

  def general
    @site_name = SystemSetting.site_name
    @site_description = SystemSetting.site_description
  end

  def archive_sync
    @sync_status = PowerSyncService.instance.sync_status
    @system_settings = {
      archive_role: SystemSetting.archive_role,
      master_archive_url: SystemSetting.master_archive_url,
      archive_node_id: SystemSetting.archive_node_id,
      sync_enabled: SystemSetting.sync_enabled?,
      sync_interval: SystemSetting.sync_interval,
      rsync_enabled: SystemSetting.rsync_enabled?,
      rsync_source_path: SystemSetting.rsync_source_path,
      rsync_dest_path: SystemSetting.rsync_dest_path,
      file_sync_enabled: SystemSetting.file_sync_enabled?,
      slave_hosts: SystemSetting.slave_hosts,
      master_host: SystemSetting.master_host
    }
  end

  def update
    case params[:tab]
    when 'theme'
      update_theme_settings
    when 'general'
      update_general_settings
    when 'api_keys'
      update_api_keys
    when 'song_types'
      update_song_types
    when 'archive_sync'
      update_archive_sync_settings
    else
      flash[:error] = "Invalid settings tab"
    end

    redirect_back(fallback_location: settings_path)
  end

  private

  def require_admin
    unless current_user&.admin?
      flash[:error] = "Access denied. Admin privileges required."
      redirect_to root_path
    end
  end

  def set_current_tab
    @current_tab = action_name
  end

  def update_theme_settings
    theme_name = params[:theme]
    available_themes = SystemSetting.available_themes
    if theme_name.present? && available_themes.include?(theme_name)
      SystemSetting.set_current_theme(theme_name)
      flash[:success] = "Theme updated to #{theme_name}"
    else
      flash[:error] = "Invalid theme selected"
    end
  end

  def theme_params
    params.require(:theme).permit(
      :name, :display_name, :description, :version, :is_active, :is_default,
      :primary_bg, :secondary_bg, :accent_color, :accent_hover, :accent_active,
      :text_primary, :text_secondary, :text_muted, :text_inverse,
      :border_color, :shadow_color, :overlay_color, :success_color,
      :warning_color, :danger_color, :button_bg, :button_hover, :button_active,
      :highlight_color, :link_color, :link_hover
    )
  end

  def update_general_settings
    if params[:site_name].present?
      SystemSetting.set_site_name(params[:site_name])
    end
    
    if params[:site_description].present?
      SystemSetting.set_site_description(params[:site_description])
    end

    flash[:success] = "General settings updated"
  end

  def update_api_keys
    # Stub for API keys update
    flash[:info] = "API keys management coming soon"
  end

  def update_song_types
    # Stub for song types update
    flash[:info] = "Song types management coming soon"
  end

  def update_archive_sync_settings
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
      
      # Update file sync settings
      SystemSetting.set('file_sync_enabled', params[:file_sync_enabled] == '1', 'Enable file synchronization')
      
      if params[:slave_hosts].present?
        SystemSetting.set('slave_hosts', params[:slave_hosts], 'Comma-separated list of slave hosts')
      end
      
      if params[:master_host].present?
        SystemSetting.set('master_host', params[:master_host], 'Master archive host')
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
    
    redirect_back(fallback_location: settings_path)
  end

  def force_file_sync
    begin
      PowerSyncService.instance.force_file_sync
      flash[:success] = "Manual file sync initiated"
    rescue => e
      flash[:error] = "File sync failed: #{e.message}"
    end
    
    redirect_back(fallback_location: settings_path)
  end

  # Key management actions
  def generate_slave_key
    name = params[:name]
    node_id = params[:node_id]
    
    if name.blank? || node_id.blank?
      redirect_to settings_path, alert: 'Name and Node ID are required'
      return
    end
    
    # Generate key and get original (one-time)
    original_key = SlaveKey.generate_key(name, node_id)
    
    # Store in session for one-time display
    session[:new_slave_key] = original_key
    session[:new_slave_key_name] = name
    
    redirect_to settings_path, notice: "Key generated for #{name}"
  end

  def regenerate_slave_key
    slave_key = SlaveKey.find(params[:id])
    original_key = slave_key.regenerate_key
    
    # Store in session for one-time display
    session[:new_slave_key] = original_key
    session[:new_slave_key_name] = slave_key.name
    
    redirect_to settings_path, notice: "Key regenerated for #{slave_key.name}"
  end

  def deactivate_slave_key
    slave_key = SlaveKey.find(params[:id])
    slave_key.deactivate
    redirect_to settings_path, notice: "Key deactivated for #{slave_key.name}"
  end

  def reactivate_slave_key
    slave_key = SlaveKey.find(params[:id])
    slave_key.reactivate
    redirect_to settings_path, notice: "Key reactivated for #{slave_key.name}"
  end

  def generate_jukebox_key
    name = params[:name]
    allowed_archives = params[:allowed_archives]&.split(',')&.map(&:strip) || []
    
    if name.blank?
      redirect_to settings_path, alert: 'Name is required'
      return
    end
    
    # Generate key and get original (one-time)
    original_key = JukeboxKey.generate_key(name, allowed_archives)
    
    # Store in session for one-time display
    session[:new_jukebox_key] = original_key
    session[:new_jukebox_key_name] = name
    
    redirect_to settings_path, notice: "Key generated for #{name}"
  end

  def regenerate_jukebox_key
    jukebox_key = JukeboxKey.find(params[:id])
    original_key = jukebox_key.regenerate_key
    
    # Store in session for one-time display
    session[:new_jukebox_key] = original_key
    session[:new_jukebox_key_name] = jukebox_key.name
    
    redirect_to settings_path, notice: "Key regenerated for #{jukebox_key.name}"
  end

  def deactivate_jukebox_key
    jukebox_key = JukeboxKey.find(params[:id])
    jukebox_key.deactivate
    redirect_to settings_path, notice: "Key deactivated for #{jukebox_key.name}"
  end

  def reactivate_jukebox_key
    jukebox_key = JukeboxKey.find(params[:id])
    jukebox_key.reactivate
    redirect_to settings_path, notice: "Key reactivated for #{jukebox_key.name}"
  end

  def perform_initial_sync
    begin
      success = PowerSyncService.instance.perform_initial_sync
      
      if success
        flash[:success] = "Initial sync completed successfully"
      else
        flash[:error] = "Initial sync failed. Check logs for details."
      end
      
    rescue => e
      flash[:error] = "Initial sync failed: #{e.message}"
    end
    
    redirect_back(fallback_location: settings_path)
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
