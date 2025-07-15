class RemoveUniqueConstraintFromSongs < ActiveRecord::Migration[8.0]
  def change
    remove_index :songs, [:album_id, :track_number], name: "index_songs_on_album_id_and_track_number"
    add_index :songs, [:album_id, :track_number], name: "index_songs_on_album_id_and_track_number"
  end
end
