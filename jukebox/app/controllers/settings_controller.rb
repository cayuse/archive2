class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin, except: [:index]

  def index
    @themes = Theme.by_display_name
    @current_theme = Theme.current
  end

  def activate_theme
    theme = Theme.find(params[:id])
    
    # Deactivate all themes
    Theme.update_all(is_active: false)
    
    # Activate the selected theme
    theme.update!(is_active: true)
    
    redirect_to settings_path, notice: "Theme '#{theme.display_name}' activated successfully!"
  end

  private

  def ensure_admin
    unless current_user&.admin?
      redirect_to root_path, alert: "Access denied. Admin privileges required."
    end
  end
end
