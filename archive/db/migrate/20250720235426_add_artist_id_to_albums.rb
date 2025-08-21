class AddArtistIdToAlbums < ActiveRecord::Migration[8.0]
  def change
    add_reference :albums, :artist, null: true, foreign_key: true, type: :uuid
  end
end
