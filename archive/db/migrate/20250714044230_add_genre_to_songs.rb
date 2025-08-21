class AddGenreToSongs < ActiveRecord::Migration[8.0]
  def change
    add_reference :songs, :genre, null: false, foreign_key: true, type: :uuid
  end
end
