class CreateAlbumsGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :albums_genres do |t|
      t.references :album, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true

      t.timestamps
    end
    
    # Add indexes for performance
    add_index :albums_genres, [:album_id, :genre_id], unique: true
  end
end
