class ThemeMigrationService
  def self.migrate_all_themes
    themes_dir = Rails.root.join('app', 'assets', 'stylesheets', 'themes')
    images_dir = Rails.root.join('app', 'assets', 'images', 'themes')
    
    migrated_themes = []
    errors = []
    
    # Find all theme directories
    theme_names = []
    
    # From stylesheets directory
    if Dir.exist?(themes_dir)
      theme_names += Dir.entries(themes_dir).select do |entry|
        next if entry.start_with?('.')
        theme_css_path = File.join(themes_dir, entry, 'theme.css')
        File.exist?(theme_css_path)
      end
    end
    
    # From images directory
    if Dir.exist?(images_dir)
      theme_names += Dir.entries(images_dir).select do |entry|
        next if entry.start_with?('.')
        Dir.exist?(File.join(images_dir, entry))
      end
    end
    
    theme_names.uniq.each do |theme_name|
      begin
        result = migrate_theme(theme_name)
        migrated_themes << result if result
      rescue => e
        errors << { theme: theme_name, error: e.message }
        Rails.logger.error "Failed to migrate theme #{theme_name}: #{e.message}"
      end
    end
    
    {
      migrated_themes: migrated_themes,
      errors: errors,
      total_themes: theme_names.uniq.length,
      successful_migrations: migrated_themes.length
    }
  end
  
  def self.migrate_theme(theme_name)
    Rails.logger.info "Migrating theme: #{theme_name}"
    
    # Check if theme already exists in database
    existing_theme = Theme.find_by(name: theme_name)
    if existing_theme
      Rails.logger.info "Theme #{theme_name} already exists in database, skipping"
      return existing_theme
    end
    
    # Create new theme
    theme = Theme.new(
      name: theme_name,
      display_name: theme_name.titleize,
      description: "Migrated from filesystem",
      version: '1.0.0',
      is_default: theme_name == 'default'
    )
    
    # Import theme data from filesystem
    if theme.import_from_filesystem(theme_name)
      theme.save!
      Rails.logger.info "Successfully migrated theme: #{theme_name}"
      theme
    else
      Rails.logger.warn "Failed to import theme data for: #{theme_name}"
      nil
    end
  end
  
  def self.create_default_theme
    # Create a default theme if none exists
    return if Theme.exists?
    
    Rails.logger.info "Creating default theme"
    
    theme = Theme.create!(
      name: 'default',
      display_name: 'Default Theme',
      description: 'Default theme created automatically',
      version: '1.0.0',
      is_default: true,
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
        /* Default theme custom styles */
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
    
    # Create a default logo
    create_default_logo(theme)
    
    Rails.logger.info "Default theme created successfully"
    theme
  end
  
  def self.create_default_logo(theme)
    # Create a simple SVG logo
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
  
  def self.cleanup_filesystem_themes
    # Optionally remove filesystem themes after successful migration
    themes_dir = Rails.root.join('app', 'assets', 'stylesheets', 'themes')
    images_dir = Rails.root.join('app', 'assets', 'images', 'themes')
    
    cleaned_dirs = []
    
    if Dir.exist?(themes_dir)
      Dir.entries(themes_dir).each do |entry|
        next if entry.start_with?('.')
        theme_path = File.join(themes_dir, entry)
        if Dir.exist?(theme_path) && Theme.find_by(name: entry)
          FileUtils.rm_rf(theme_path)
          cleaned_dirs << "stylesheets/themes/#{entry}"
        end
      end
    end
    
    if Dir.exist?(images_dir)
      Dir.entries(images_dir).each do |entry|
        next if entry.start_with?('.')
        theme_path = File.join(images_dir, entry)
        if Dir.exist?(theme_path) && Theme.find_by(name: entry)
          FileUtils.rm_rf(theme_path)
          cleaned_dirs << "images/themes/#{entry}"
        end
      end
    end
    
    {
      cleaned_directories: cleaned_dirs,
      total_cleaned: cleaned_dirs.length
    }
  end
  
  def self.validate_migration
    # Validate that all themes were migrated correctly
    themes_dir = Rails.root.join('app', 'assets', 'stylesheets', 'themes')
    images_dir = Rails.root.join('app', 'assets', 'images', 'themes')
    
    filesystem_themes = []
    database_themes = Theme.pluck(:name)
    
    # Check stylesheets directory
    if Dir.exist?(themes_dir)
      filesystem_themes += Dir.entries(themes_dir).select do |entry|
        next if entry.start_with?('.')
        theme_css_path = File.join(themes_dir, entry, 'theme.css')
        File.exist?(theme_css_path)
      end
    end
    
    # Check images directory
    if Dir.exist?(images_dir)
      filesystem_themes += Dir.entries(images_dir).select do |entry|
        next if entry.start_with?('.')
        Dir.exist?(File.join(images_dir, entry))
      end
    end
    
    filesystem_themes.uniq!
    
    {
      filesystem_themes: filesystem_themes,
      database_themes: database_themes,
      missing_in_database: filesystem_themes - database_themes,
      extra_in_database: database_themes - filesystem_themes,
      all_migrated: (filesystem_themes - database_themes).empty?
    }
  end
end 