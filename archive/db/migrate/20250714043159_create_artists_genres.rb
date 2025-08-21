class CreateArtistsGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :artists_genres, id: false do |t|
      t.uuid :artist_id, null: false
      t.uuid :genre_id, null: false

      t.timestamps
    end
    
    # Add foreign key constraints
    add_foreign_key :artists_genres, :artists, column: :artist_id, primary_key: :id, on_delete: :cascade
    add_foreign_key :artists_genres, :genres, column: :genre_id, primary_key: :id, on_delete: :cascade
    
    # Add indexes for performance
    add_index :artists_genres, [:artist_id, :genre_id], unique: true
  end
end
