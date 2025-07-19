class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  # Class methods for easy setting management
  class << self
    def get(key, default = nil)
      setting = find_by(key: key)
      setting&.value || default
    end

    def set(key, value, description = nil)
      setting = find_or_initialize_by(key: key)
      setting.value = value
      setting.description = description if description
      setting.save!
    end

    def current_theme
      get('current_theme', 'default')
    end

    def set_current_theme(theme_name)
      set('current_theme', theme_name, 'Currently active theme')
    end

    def available_themes
      # Discover themes from filesystem and cache in database
      discovered_themes = discover_themes_from_filesystem
      cached_themes = get('available_themes', 'default')
      
      # Update cache if themes have changed
      if discovered_themes.sort != cached_themes.split(',').sort
        set('available_themes', discovered_themes.join(','), 'List of available themes')
      end
      
      discovered_themes
    end

    def discover_themes_from_filesystem
      themes_dir = Rails.root.join('app', 'assets', 'stylesheets', 'themes')
      return ['default'] unless Dir.exist?(themes_dir)

      themes = Dir.entries(themes_dir).select do |entry|
        next if entry.start_with?('.')
        theme_css_path = File.join(themes_dir, entry, 'theme.css')
        File.exist?(theme_css_path)
      end
      
      themes.empty? ? ['default'] : themes
    end

    def set_available_themes(themes)
      set('available_themes', themes.join(','), 'List of available themes')
    end

    def site_name
      get('site_name', 'Music Archive')
    end

    def set_site_name(name)
      set('site_name', name, 'Site name displayed in navigation')
    end

    def site_description
      get('site_description', 'A comprehensive music archive system')
    end

    def set_site_description(description)
      set('site_description', description, 'Site description for SEO')
    end
    
    # Archive sync methods
    def archive_role
      get('archive_role', 'standalone')
    end
    
    def master_archive_url
      get('master_archive_url', '')
    end
    
    def archive_node_id
      get('archive_node_id', Socket.gethostname)
    end
    
    def sync_enabled?
      get('sync_enabled', 'false') == 'true'
    end
    
    def sync_interval
      get('sync_interval', '300').to_i
    end
    
    def rsync_enabled?
      get('rsync_enabled', 'false') == 'true'
    end
    
    def rsync_source_path
      get('rsync_source_path', Rails.root.join('storage').to_s)
    end
    
    def rsync_dest_path
      get('rsync_dest_path', '')
    end
    
    # Check if this is a master archive
    def master?
      archive_role == 'master'
    end
    
    # Check if this is a slave archive
    def slave?
      archive_role == 'slave'
    end
    
    # Check if this is a standalone archive
    def standalone?
      archive_role == 'standalone'
    end

    # File sync settings
    def file_sync_enabled?
      get('file_sync_enabled', 'false') == 'true'
    end

    def file_sync_in_progress?
      get('file_sync_in_progress', 'false') == 'true'
    end

    def last_file_sync_time
      timestamp = get('last_file_sync_time')
      timestamp ? Time.parse(timestamp) : nil
    end

    def file_sync_status
      get('file_sync_status', 'idle')
    end

    def slave_hosts
      hosts = get('slave_hosts')
      hosts.present? ? hosts.split(',') : []
    end

    def master_host
      get('master_host', '')
    end
  end
end
