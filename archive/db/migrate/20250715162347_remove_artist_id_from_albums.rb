class RemoveArtistIdFromAlbums < ActiveRecord::Migration[8.0]
  def change
    remove_reference :albums, :artist, null: false, foreign_key: true
  end
end
