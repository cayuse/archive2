class AddArchiveSyncSettings < ActiveRecord::Migration[8.0]
  def up
    # Add archive sync settings
    settings = [
      {
        key: 'archive_role',
        value: 'standalone',
        description: 'Archive role: standalone, master, or slave'
      },
      {
        key: 'master_archive_url',
        value: '',
        description: 'URL of master archive (for slave nodes)'
      },
      {
        key: 'archive_node_id',
        value: Socket.gethostname,
        description: 'Unique identifier for this archive node'
      },
      {
        key: 'sync_enabled',
        value: 'false',
        description: 'Enable archive-to-archive synchronization'
      },
      {
        key: 'sync_interval',
        value: '300',
        description: 'Sync interval in seconds (5 minutes default)'
      },
      {
        key: 'rsync_enabled',
        value: 'false',
        description: 'Enable rsync file synchronization'
      },
      {
        key: 'rsync_source_path',
        value: Rails.root.join('storage').to_s,
        description: 'Source path for rsync (Active Storage base path)'
      },
      {
        key: 'rsync_dest_path',
        value: '',
        description: 'Destination path for rsync (on slave nodes)'
      }
    ]
    
    settings.each do |setting|
      # Use raw SQL to avoid model dependency during migration
      execute <<-SQL
        INSERT INTO system_settings (key, value, description, created_at, updated_at)
        VALUES ('#{setting[:key]}', '#{setting[:value]}', '#{setting[:description]}', NOW(), NOW())
        ON CONFLICT (key) DO UPDATE SET
          value = EXCLUDED.value,
          description = EXCLUDED.description,
          updated_at = NOW()
      SQL
    end
  end
  
  def down
    # Remove archive sync settings
    keys_to_remove = [
      'archive_role',
      'master_archive_url', 
      'archive_node_id',
      'sync_enabled',
      'sync_interval',
      'rsync_enabled',
      'rsync_source_path',
      'rsync_dest_path'
    ]
    
    # Use raw SQL to avoid model dependency during migration
    keys_to_remove.each do |key|
      execute "DELETE FROM system_settings WHERE key = '#{key}'"
    end
  end
end
