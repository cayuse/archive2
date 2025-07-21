module ApplicationHelper
  def current_theme
    # Always try to get theme from database first
    theme = Theme.current
    return theme.name if theme
    
    # Fallback to system setting
    SystemSetting.current_theme || 'default'
  end
  
  def theme_css_path
    # Always use the database-driven CSS endpoint with cache busting
    theme = Theme.current
    cache_buster = theme&.updated_at&.to_i || Time.current.to_i
    "/themes/#{current_theme}.css?v=#{cache_buster}"
  end
  
  def theme_asset_path(asset_type, filename)
    "/themes/#{current_theme}/assets/#{asset_type}/#{filename}"
  end
  
  def theme_logo_path
    # Try to get logo from database first
    theme = Theme.current
    if theme&.logos&.any?
      logo = theme.logos.first
      return theme_asset_path('logo', logo.filename)
    end
    
    # Fallback to a default logo or placeholder
    "/icon.svg"
  end
  
  def theme_icon_path(icon)
    # Try to get icon from database first
    theme = Theme.current
    if theme&.icons&.any? { |i| i.filename == icon }
      return theme_asset_path('icon', icon)
    end
    
    # Fallback to a default icon or placeholder
    "/icon.svg"
  end
  
  def theme_image_path(image)
    # Try to get image from database first
    theme = Theme.current
    if theme&.images&.any? { |i| i.filename == image }
      return theme_asset_path('image', image)
    end
    
    # Fallback to a default image or placeholder
    "/icon.svg"
  end
end
