class SettingsController < ApplicationController
  before_action :require_admin
  before_action :set_current_tab

  def show
    # Show the main settings page with navigation
    @current_tab = 'index'
  end

  def theme
    @available_themes = SystemSetting.available_themes
    @current_theme = SystemSetting.current_theme
  end

  def api_keys
    # Stub for API keys management
  end

  def song_types
    # Stub for song types management
  end

  def general
    @site_name = SystemSetting.site_name
    @site_description = SystemSetting.site_description
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
end
