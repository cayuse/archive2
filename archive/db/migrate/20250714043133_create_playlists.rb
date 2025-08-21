class CreatePlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :description
      t.boolean :is_public, default: false, null: false

      t.timestamps
    end
    
    # Add indexes for performance and data integrity
    add_index :playlists, :name
    add_index :playlists, :is_public
    add_index :playlists, [:user_id, :name], unique: true
  end
end
