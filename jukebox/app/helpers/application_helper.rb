module ApplicationHelper
  def format_duration(seconds)
    return "0:00" unless seconds
    
    minutes = (seconds / 60).to_i
    remaining_seconds = (seconds % 60).to_i
    
    "#{minutes}:#{remaining_seconds.to_s.rjust(2, '0')}"
  end

  # Theme helpers
  def current_theme
    Theme.current&.name || 'default'
  end

  def theme_css_path
    theme = Theme.current
    cache_buster = theme&.updated_at&.to_i || Time.current.to_i
    "/themes/#{current_theme}.css?v=#{cache_buster}"
  end

  def theme_logo_path
    theme = Theme.current
    logo = theme&.logos&.first
    return '/icon.png' unless logo
    "/themes/#{current_theme}/assets/logo/#{logo.filename}"
  end

  def theme_asset_path(theme_name, asset_type, filename)
    "/themes/#{theme_name}/assets/#{asset_type}/#{filename}"
  end
end
