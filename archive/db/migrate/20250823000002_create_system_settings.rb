class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    # Ensure pgcrypto extension is enabled for UUID generation
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :system_settings, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :key, null: false
      t.text :value
      t.text :description

      t.timestamps
    end
    
    # Add unique constraint on key
    add_index :system_settings, :key, unique: true
  end
end
