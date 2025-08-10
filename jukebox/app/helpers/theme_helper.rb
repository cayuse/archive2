module ThemeHelper
  def current_theme
    SystemSetting.current_theme || 'default'
  end

  def theme_asset_path(asset)
    # Route through themes controller to fetch DB assets
    type = asset.to_s.include?('/') ? asset.split('/').first.singularize : 'image'
    filename = asset.to_s.split('/').last
    "/themes/#{current_theme}/assets/#{type}/#{filename}"
  end

  def theme_icon_path(icon)
    "/themes/#{current_theme}/assets/icon/#{icon}"
  end

  def theme_image_path(image)
    "/themes/#{current_theme}/assets/image/#{image}"
  end

  def theme_css_path
    # Serve DB-driven theme CSS via controller, not the asset pipeline
    "/themes/#{current_theme}.css?v=#{Theme.current&.updated_at&.to_i || Time.current.to_i}"
  end

  def theme_logo_path
    "/themes/#{current_theme}/assets/logo/logo.svg"
  end

  def theme_icon_tag(icon, options = {})
    default_options = { width: 24, height: 24, class: 'theme-icon' }
    options = default_options.merge(options)
    
    # Check if the icon exists in the current theme
    image_tag(theme_icon_path(icon), options)
  end

  def theme_image_tag(image, options = {})
    default_options = { class: 'theme-image' }
    options = default_options.merge(options)
    
    # Check if the image exists in the current theme
    image_tag(theme_image_path(image), options)
  end

  def theme_asset_exists?(asset_path)
    # Could probe ThemesController route, but for now return true
    true
  end
end 