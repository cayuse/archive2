module ThemeHelper
  def current_theme
    SystemSetting.current_theme || 'default'
  end

  def theme_asset_path(asset)
    asset_path("themes/#{current_theme}/#{asset}")
  end

  def theme_icon_path(icon)
    asset_path("themes/#{current_theme}/icons/#{icon}")
  end

  def theme_image_path(image)
    asset_path("themes/#{current_theme}/images/#{image}")
  end

  def theme_css_path
    asset_path("themes/#{current_theme}/theme.css")
  end

  def theme_logo_path
    theme_asset_path('logo.svg')
  end

  def theme_icon_tag(icon, options = {})
    default_options = { width: 24, height: 24, class: 'theme-icon' }
    options = default_options.merge(options)
    
    image_tag(theme_icon_path(icon), options)
  end

  def theme_image_tag(image, options = {})
    default_options = { class: 'theme-image' }
    options = default_options.merge(options)
    
    image_tag(theme_image_path(image), options)
  end
end 