class CreateAlbumsGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :albums_genres, id: false do |t|
      t.uuid :album_id, null: false
      t.uuid :genre_id, null: false

      t.timestamps
    end
    
    # Add composite primary key (required for logical replication)
    execute "ALTER TABLE albums_genres ADD CONSTRAINT albums_genres_pkey PRIMARY KEY (album_id, genre_id);"
    
    # Add foreign key constraints
    add_foreign_key :albums_genres, :albums, column: :album_id, primary_key: :id, on_delete: :cascade
    add_foreign_key :albums_genres, :genres, column: :genre_id, primary_key: :id, on_delete: :cascade
    
    # Add indexes for performance
    add_index :albums_genres, [:album_id, :genre_id], unique: true
  end
end
