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
    
    # Check if the icon exists in the current theme
    icon_path = "themes/#{current_theme}/icons/#{icon}"
    if Rails.application.assets.find_asset(icon_path)
      image_tag(theme_icon_path(icon), options)
    else
      # Fallback to default theme if icon doesn't exist in current theme
      fallback_path = asset_path("themes/default/icons/#{icon}")
      image_tag(fallback_path, options)
    end
  end

  def theme_image_tag(image, options = {})
    default_options = { class: 'theme-image' }
    options = default_options.merge(options)
    
    # Check if the image exists in the current theme
    image_path = "themes/#{current_theme}/images/#{image}"
    if Rails.application.assets.find_asset(image_path)
      image_tag(theme_image_path(image), options)
    else
      # Fallback to default theme if image doesn't exist in current theme
      fallback_path = asset_path("themes/default/images/#{image}")
      image_tag(fallback_path, options)
    end
  end

  def theme_asset_exists?(asset_path)
    Rails.application.assets.find_asset(asset_path).present?
  end
end 