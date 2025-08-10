class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true
  
  # Class methods for easy setting access
  def self.get(key, default = nil)
    setting = find_by(key: key)
    setting&.value || default
  end
  
  def self.set(key, value, description = nil)
    setting = find_or_initialize_by(key: key)
    setting.value = value.to_s
    setting.description = description if description
    setting.save!
  end
  
  def self.archive_role
    get('archive_role', 'standalone')
  end
  
  def self.master_archive_url
    get('master_archive_url', '')
  end
  
  def self.archive_node_id
    get('archive_node_id', Socket.gethostname)
  end
  
  def self.sync_enabled?
    get('sync_enabled', 'false') == 'true'
  end
  
  def self.sync_interval
    get('sync_interval', '300').to_i
  end
  
  def self.rsync_enabled?
    get('rsync_enabled', 'false') == 'true'
  end
  
  def self.rsync_source_path
    get('rsync_source_path', Rails.root.join('storage').to_s)
  end
  
  def self.rsync_dest_path
    get('rsync_dest_path', '')
  end
  
  # Check if this is a master archive
  def self.master?
    archive_role == 'master'
  end
  
  # Check if this is a slave archive
  def self.slave?
    archive_role == 'slave'
  end
  
  # Check if this is a standalone archive
  def self.standalone?
    archive_role == 'standalone'
  end

  # --- Theme and site settings ---
  def self.current_theme
    get('current_theme', 'default')
  end

  def self.set_current_theme(theme)
    set('current_theme', theme)
  end

  def self.available_themes
    themes_root = Rails.root.join('app', 'assets', 'themes')
    return [] unless Dir.exist?(themes_root)
    Dir.children(themes_root)
      .select { |entry| File.directory?(File.join(themes_root, entry)) }
      .sort
  rescue => e
    Rails.logger.warn("Failed to list available themes: #{e.message}")
    []
  end

  def self.site_name
    get('site_name', 'Jukebox')
  end

  def self.site_description
    get('site_description', 'A live music jukebox system')
  end

  # Jukebox playback settings
  def self.min_random_queue_size
    get('min_random_queue_size', '7').to_i
  end

  def self.recently_played_window
    get('recently_played_window', '10').to_i
  end

  # Queue auto-refill controls
  def self.min_queue_length
    get('min_queue_length', '5').to_i
  end

  def self.refill_queue_to
    get('refill_queue_to', '10').to_i
  end
end
