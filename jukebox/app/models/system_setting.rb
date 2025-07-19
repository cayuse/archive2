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
end
