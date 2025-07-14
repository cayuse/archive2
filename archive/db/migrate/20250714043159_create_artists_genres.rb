class CreateArtistsGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :artists_genres do |t|
      t.references :artist, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true

      t.timestamps
    end
    
    # Add indexes for performance
    add_index :artists_genres, [:artist_id, :genre_id], unique: true
  end
end
