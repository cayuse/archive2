class CreateSyncChanges < ActiveRecord::Migration[8.0]
  def change
    # Ensure pgcrypto extension is enabled for UUID generation
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :sync_changes, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :table_name, null: false
      t.string :record_id, null: false
      t.string :change_type, null: false
      t.jsonb :change_data
      t.timestamp :applied_at
      t.text :applied_to_slaves, array: true, default: []

      t.timestamps
    end

    add_index :sync_changes, [:table_name, :record_id, :created_at]
    add_index :sync_changes, :created_at
    add_index :sync_changes, :applied_at
  end
end
