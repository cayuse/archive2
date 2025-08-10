class SystemConfigController < ApplicationController
  before_action :require_admin
  
  def index
    @current_theme = SystemSetting.current_theme
    @available_themes = Theme.by_display_name
    @site_name = SystemSetting.site_name
    @site_description = SystemSetting.site_description
  end
  
  def themes
    @current_theme = SystemSetting.current_theme
    @available_themes = Theme.by_display_name
    
    if request.post?
      new_theme_name = params[:theme]
      theme = Theme.find_by(name: new_theme_name)
      if theme
        SystemSetting.set_current_theme(theme.name)
        redirect_to system_themes_path, notice: "Theme updated to #{theme.display_name}"
      else
        flash.now[:alert] = "Invalid theme selected"
      end
    end
  end
  
  def settings
    @site_name = SystemSetting.site_name
    @site_description = SystemSetting.site_description
    @min_queue_length = SystemSetting.min_queue_length
    @refill_queue_to = SystemSetting.refill_queue_to
    
    if request.post?
      SystemSetting.set_site_name(params[:site_name]) if params[:site_name].present?
      SystemSetting.set_site_description(params[:site_description]) if params[:site_description].present?
      if params[:min_queue_length].present?
        val = params[:min_queue_length].to_i
        SystemSetting.set('min_queue_length', val.clamp(0, 10_000), 'Minimum queue length before auto-refill')
      end
      if params[:refill_queue_to].present?
        val = params[:refill_queue_to].to_i
        SystemSetting.set('refill_queue_to', val.clamp(0, 10_000), 'Target queue length after auto-refill')
      end
      
      redirect_to system_settings_path, notice: "Settings updated successfully"
    end
  end

  def random_sources
    @all_playlists = ArchivePlaylist.by_name
    @selected_ids = JukeboxSelectedPlaylist.pluck(:playlist_id)
    if request.post?
      ids = Array(params[:playlist_ids]).map(&:to_i).uniq
      JukeboxSelectedPlaylist.delete_all
      ids.each { |pid| JukeboxSelectedPlaylist.create!(playlist_id: pid) }
      redirect_to system_random_sources_path, notice: 'Random sources updated'
    end
  end
end
