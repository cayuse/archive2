class SystemConfigController < ApplicationController
  before_action :require_admin
  
  def index
    @current_theme = SystemSetting.current_theme
    @available_themes = SystemSetting.available_themes
    @site_name = SystemSetting.site_name
    @site_description = SystemSetting.site_description
  end
  
  def themes
    @current_theme = SystemSetting.current_theme
    @available_themes = SystemSetting.available_themes
    
    if request.post?
      new_theme = params[:theme]
      if @available_themes.include?(new_theme)
        SystemSetting.set_current_theme(new_theme)
        redirect_to system_themes_path, notice: "Theme updated to #{new_theme}"
      else
        flash.now[:alert] = "Invalid theme selected"
      end
    end
  end
  
  def settings
    @site_name = SystemSetting.site_name
    @site_description = SystemSetting.site_description
    
    if request.post?
      SystemSetting.set_site_name(params[:site_name]) if params[:site_name].present?
      SystemSetting.set_site_description(params[:site_description]) if params[:site_description].present?
      
      redirect_to system_settings_path, notice: "Settings updated successfully"
    end
  end
end
