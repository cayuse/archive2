class CreatePlaylistsSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists_songs do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :song, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end
    
    # Add indexes for performance and ordering
    add_index :playlists_songs, [:playlist_id, :position]
    add_index :playlists_songs, [:playlist_id, :song_id], unique: true
    add_check_constraint :playlists_songs, "position IS NULL OR position > 0", name: "check_positive_position"
  end
end
