class CreateJukeboxTables < ActiveRecord::Migration[8.0]
  def change
    # Jukebox playlists (references archive playlists)
    create_table :jukebox_playlists do |t|
      t.string :name, null: false
      t.bigint :archive_playlist_id, null: false
      t.boolean :active, default: true
      t.boolean :jukebox_enabled, default: false
      t.integer :crossfade_duration, default: 0
      t.integer :volume, default: 80
      t.timestamps

      t.index :archive_playlist_id, unique: true
      t.index :jukebox_enabled
      t.index :active
    end

    # Jukebox playlist songs (join table)
    create_table :jukebox_playlist_songs do |t|
      t.bigint :jukebox_playlist_id, null: false
      t.bigint :song_id, null: false  # References archive songs
      t.integer :position, null: false
      t.timestamps

      t.index :jukebox_playlist_id
      t.index :song_id
      t.index [:jukebox_playlist_id, :position]
      t.index [:jukebox_playlist_id, :song_id], unique: true
    end

    # Queue items (user-requested songs)
    create_table :jukebox_queue_items do |t|
      t.bigint :song_id, null: false  # References archive songs
      t.bigint :user_id  # Optional - who requested it
      t.integer :position, null: false
      t.string :status, default: 'pending'  # pending, playing, played, skipped
      t.datetime :played_at
      t.timestamps

      t.index :song_id
      t.index :user_id
      t.index :position
      t.index :status
      t.index [:status, :position]
    end

    # Cached songs (local storage)
    create_table :jukebox_cached_songs do |t|
      t.bigint :song_id, null: false  # References archive songs
      t.string :local_path
      t.string :original_path
      t.bigint :file_size
      t.string :status, default: 'downloading'  # downloading, completed, failed
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps

      t.index :song_id, unique: true
      t.index :status
      t.index :local_path
    end

    # Add foreign key constraints
    add_foreign_key :jukebox_playlist_songs, :jukebox_playlists, on_delete: :cascade
    add_foreign_key :jukebox_queue_items, :users, on_delete: :nullify
    add_foreign_key :jukebox_cached_songs, :songs, on_delete: :cascade
  end
end


