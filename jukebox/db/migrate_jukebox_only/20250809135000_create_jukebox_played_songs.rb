class CreateJukeboxPlayedSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :jukebox_played_songs do |t|
      t.uuid :song_id, null: false  # References archive songs (UUID)
      t.datetime :played_at, null: false
      t.string :source, null: false  # 'queue' or 'random'
      t.timestamps
      t.index :song_id
      t.index :played_at
    end
    
    # Add foreign key constraint to archive songs table
    add_foreign_key :jukebox_played_songs, :songs, on_delete: :cascade, type: :uuid
  end
end


