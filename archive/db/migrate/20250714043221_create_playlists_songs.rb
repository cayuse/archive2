class CreatePlaylistsSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists_songs, id: false do |t|
      t.uuid :playlist_id, null: false
      t.uuid :song_id, null: false
      t.integer :position

      t.timestamps
    end
    
    # Add foreign key constraints
    add_foreign_key :playlists_songs, :playlists, column: :playlist_id, primary_key: :id, on_delete: :cascade
    add_foreign_key :playlists_songs, :songs, column: :song_id, primary_key: :id, on_delete: :cascade
    
    # Add indexes for performance and ordering
    add_index :playlists_songs, [:playlist_id, :position]
    add_index :playlists_songs, [:playlist_id, :song_id], unique: true
    add_check_constraint :playlists_songs, "position IS NULL OR position > 0", name: "check_positive_position"
  end
end
