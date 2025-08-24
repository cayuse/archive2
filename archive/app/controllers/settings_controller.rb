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
      # Set the global current theme in settings for single-source truth
      SystemSetting.set_current_theme(theme.name)
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

  def theme_params
    params.require(:theme).permit(
      :name, :display_name, :description, :version, :is_active, :is_default,
      :primary_bg, :secondary_bg, :accent_color, :accent_hover, :accent_active,
      :text_primary, :text_secondary, :text_muted, :text_inverse,
      :border_color, :shadow_color, :overlay_color, :success_color,
      :warning_color, :danger_color, :button_bg, :button_hover, :button_active,
      :highlight_color, :link_color, :link_hover,
      :heading_color, :card_header_text
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









  # Key management actions


















  private




end
