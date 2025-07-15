class MakeAlbumAndGenreOptionalInSongs < ActiveRecord::Migration[8.0]
  def change
    change_column_null :songs, :album_id, true
    change_column_null :songs, :genre_id, true
  end
end
