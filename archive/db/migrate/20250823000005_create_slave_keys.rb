class CreateSlaveKeys < ActiveRecord::Migration[8.0]
  def change
    # Ensure pgcrypto extension is enabled for UUID generation
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :slave_keys, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.string :key_hash, null: false
      t.string :node_id, null: false
      t.timestamp :last_used_at
      t.boolean :is_active, default: true, null: false

      t.timestamps
    end
    
    add_index :slave_keys, :node_id, unique: true
    add_index :slave_keys, :key_hash
  end
end
