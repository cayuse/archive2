class CreateAjbPlayedSongs < ActiveRecord::Migration[7.0]
  def change
    create_table :ajb_played_songs, id: :uuid do |t|
      t.uuid :jukebox_id, null: false
      t.uuid :song_id, null: false
      t.timestamp :played_at, null: false
      t.string :source, null: false, default: 'random' # 'random' or 'requested'

      t.timestamps
    end

    # Indexes for performance
    add_index :ajb_played_songs, :jukebox_id
    add_index :ajb_played_songs, :song_id
    add_index :ajb_played_songs, :played_at
    add_index :ajb_played_songs, [:jukebox_id, :played_at]
    
    # Foreign key constraints
    add_foreign_key :ajb_played_songs, :jukeboxes, column: :jukebox_id, on_delete: :cascade
    add_foreign_key :ajb_played_songs, :songs, column: :song_id, on_delete: :cascade
    
    # Check constraints
    add_check_constraint :ajb_played_songs, "source IN ('random', 'requested')", name: "check_valid_source"
  end
end
