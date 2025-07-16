class AddSearchIndexesToSongs < ActiveRecord::Migration[8.0]
  def change
    # Enable pg_trgm extension for trigram search if not already enabled
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')
    
    # Add indexes for better search performance
    add_index :songs, :created_at, name: 'index_songs_on_created_at_desc'
    add_index :songs, [:processing_status, :created_at], name: 'index_songs_on_status_and_created_at'
    
    # Add indexes for foreign key lookups in search (using trigram indexes for better ILIKE performance)
    add_index :artists, :name, name: 'index_artists_on_name_gin', using: :gin, opclass: :gin_trgm_ops
    add_index :albums, :title, name: 'index_albums_on_title_gin', using: :gin, opclass: :gin_trgm_ops
    add_index :genres, :name, name: 'index_genres_on_name_gin', using: :gin, opclass: :gin_trgm_ops
  end
end
