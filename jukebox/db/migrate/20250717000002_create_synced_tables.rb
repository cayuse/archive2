class CreateSyncedTables < ActiveRecord::Migration[8.0]
  def change
    # Songs table (synced from archive)
    create_table :songs do |t|
      t.string :title, null: false
      t.string :artist
      t.string :album
      t.string :genre
      t.integer :year
      t.integer :duration
      t.string :file_path, null: false
      t.bigint :file_size
      t.integer :bitrate
      t.integer :sample_rate
      t.integer :channels
      t.timestamps
    end
    
    add_index :songs, :title
    add_index :songs, :artist
    add_index :songs, :album
    add_index :songs, :genre
    add_index :songs, :year
    
    # Artists table (synced from archive)
    create_table :artists do |t|
      t.string :name, null: false
      t.text :bio
      t.timestamps
    end
    
    add_index :artists, :name, unique: true
    
    # Albums table (synced from archive)
    create_table :albums do |t|
      t.string :title, null: false
      t.references :artist, null: true, foreign_key: true
      t.integer :year
      t.string :genre
      t.string :cover_art_path
      t.timestamps
    end
    
    add_index :albums, :title
    add_index :albums, :year
    
    # Genres table (synced from archive)
    create_table :genres do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    
    add_index :genres, :name, unique: true
    
    # Playlists table (synced from archive)
    create_table :playlists do |t|
      t.string :name, null: false
      t.text :description
      t.references :user, null: true, foreign_key: true
      t.boolean :is_public, default: false
      t.timestamps
    end
    
    add_index :playlists, :name
    add_index :playlists, :is_public
    
    # Playlist songs table (synced from archive)
    create_table :playlist_songs do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :song, null: false, foreign_key: true
      t.integer :position
      t.timestamps
    end
    
    add_index :playlist_songs, [:playlist_id, :position]
    add_index :playlist_songs, [:playlist_id, :song_id], unique: true
    
    # Users table (synced from archive)
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :role, default: 'user'
      t.timestamps
    end
    
    add_index :users, :email, unique: true
    add_index :users, :role
  end
end 