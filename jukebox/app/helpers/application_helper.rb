module ApplicationHelper
  def format_duration(seconds)
    return "0:00" unless seconds
    
    minutes = (seconds / 60).to_i
    remaining_seconds = (seconds % 60).to_i
    
    "#{minutes}:#{remaining_seconds.to_s.rjust(2, '0')}"
  end

  # Theme helpers
  def current_theme
    @current_theme ||= Theme.current
    @current_theme&.name || 'default'
  end

  def theme_css_path
    theme = Theme.current
    return '/assets/application.css' unless theme
    
    # Add cache busting parameter
    "/themes/#{theme.name}.css?v=#{theme.updated_at.to_i}"
  end

  def theme_logo_path
    theme = Theme.current
    return '/icon.png' unless theme
    
    logo = theme.logos.first
    return '/icon.png' unless logo&.file&.attached?
    
    "/themes/#{theme.name}/assets/logo/#{logo.filename}"
  end

  def theme_asset_path(theme_name, asset_type, filename)
    "/themes/#{theme_name}/assets/#{asset_type}/#{filename}"
  end
end
