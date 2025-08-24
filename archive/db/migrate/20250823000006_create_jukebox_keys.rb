class CreateJukeboxKeys < ActiveRecord::Migration[8.0]
  def change
    # Ensure pgcrypto extension is enabled for UUID generation
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :jukebox_keys, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.string :key_hash, null: false
      t.text :allowed_archives, array: true, default: []
      t.timestamp :last_used_at
      t.boolean :is_active, default: true, null: false

      t.timestamps
    end
    
    add_index :jukebox_keys, :key_hash
  end
end
