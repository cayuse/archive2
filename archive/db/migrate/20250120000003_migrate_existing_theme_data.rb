class MigrateExistingThemeData < ActiveRecord::Migration[8.0]
  def up
    # Migrate existing theme data to new structure
    Theme.reset_column_information
    
    # Temporarily disable callbacks during migration
    Theme.skip_callback(:save, :after, :update_powersync_schema)
    ThemeAsset.skip_callback(:save, :after, :update_powersync_schema)
    
    Theme.find_each do |theme|
      # Set default values for new columns
      theme.update_columns(
        is_default: theme.name == 'default',
        is_active: theme.is_active_old || true,
        version: '1.0.0',
        css_variables: extract_css_variables_from_config(theme.config_old),
        custom_css: extract_custom_css_from_config(theme.config_old)
      )
    end
    
    # Create default theme if none exists
    unless Theme.exists?
      default_theme = Theme.create!(
        name: 'default',
        display_name: 'Default Theme',
        description: 'Default theme created automatically',
        is_default: true,
        is_active: true,
        version: '1.0.0',
        css_variables: {
          'primary-bg' => '#0f0f23',
          'secondary-bg' => '#1a1a2e',
          'card-bg' => '#16213e',
          'accent-color' => '#4f46e5',
          'accent-hover' => '#6366f1',
          'text-primary' => '#f8fafc',
          'text-secondary' => '#cbd5e1',
          'text-muted' => '#64748b',
          'border-color' => '#334155',
          'success-color' => '#10b981',
          'warning-color' => '#f59e0b',
          'danger-color' => '#ef4444',
          'info-color' => '#3b82f6'
        },
        custom_css: <<~CSS
          [data-theme="default"] body {
            background: var(--primary-bg);
            color: var(--text-primary);
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
          }
          
          [data-theme="default"] .card {
            background-color: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 0.5rem;
            box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
          }
          
          [data-theme="default"] .btn-primary {
            background-color: var(--accent-color);
            border-color: var(--accent-color);
          }
          
          [data-theme="default"] .btn-primary:hover {
            background-color: var(--accent-hover);
            border-color: var(--accent-hover);
          }
        CSS
      )
      
      # Create default logo
      create_default_logo(default_theme)
    end
    
    # Set current theme in system settings
    current_theme_name = SystemSetting.get('current_theme', 'default')
    current_theme = Theme.find_by(name: current_theme_name) || Theme.default.first
    
    if current_theme
      SystemSetting.set('current_theme', current_theme.name, 'Currently active theme')
    end
    
    # Re-enable callbacks after migration
    Theme.set_callback(:save, :after, :update_powersync_schema)
    ThemeAsset.set_callback(:save, :after, :update_powersync_schema)
  end
  
  def down
    # Revert theme data to old structure
    Theme.find_each do |theme|
      theme.update_columns(
        is_active_old: theme.is_active,
        config_old: theme.css_variables.to_json
      )
    end
  end
  
  private
  
  def extract_css_variables_from_config(config)
    return {} if config.blank?
    
    begin
      config_data = JSON.parse(config)
      config_data['css_variables'] || {}
    rescue JSON::ParserError
      {}
    end
  end
  
  def extract_custom_css_from_config(config)
    return nil if config.blank?
    
    begin
      config_data = JSON.parse(config)
      config_data['custom_css']
    rescue JSON::ParserError
      nil
    end
  end
  
  def create_default_logo(theme)
    svg_content = <<~SVG
      <svg width="40" height="40" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
        <rect width="40" height="40" rx="8" fill="#4f46e5"/>
        <text x="20" y="26" font-family="Arial, sans-serif" font-size="16" font-weight="bold" text-anchor="middle" fill="white">M</text>
      </svg>
    SVG
    
    theme.theme_assets.create!(
      asset_type: 'logo',
      filename: 'logo.svg',
      content_type: 'image/svg+xml',
      file_data: svg_content,
      file_size: svg_content.bytesize,
      checksum: Digest::SHA256.hexdigest(svg_content),
      metadata: {
        created_by: 'system',
        description: 'Default logo'
      }
    )
  end
end 