class CreateSyncStatusTracking < ActiveRecord::Migration[8.0]
  def change
    # Ensure pgcrypto extension is enabled for UUID generation
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :sync_status_tracking, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :sync_type, null: false  # 'database', 'file', 'initial'
      t.string :target_node_id          # For master->slave syncs
      t.string :status, null: false     # 'success', 'failed', 'in_progress'
      t.text :error_message             # Details if failed
      t.integer :attempt_count, default: 0
      t.timestamp :last_attempt_at
      t.timestamp :last_success_at
      t.timestamp :next_attempt_at      # For retry scheduling
      t.jsonb :sync_metadata            # Additional sync info
      
      t.timestamps
    end

    add_index :sync_status_tracking, [:sync_type, :target_node_id]
    add_index :sync_status_tracking, :status
    add_index :sync_status_tracking, :next_attempt_at
    add_index :sync_status_tracking, :last_success_at
  end
end
