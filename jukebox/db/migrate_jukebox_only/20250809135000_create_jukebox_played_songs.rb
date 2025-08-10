class CreateJukeboxPlayedSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :jukebox_played_songs do |t|
      t.bigint :song_id, null: false
      t.datetime :played_at, null: false
      t.string :source, null: false  # 'queue' or 'random'
      t.timestamps
      t.index :song_id
      t.index :played_at
    end
  end
end


