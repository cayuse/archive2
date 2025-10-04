class CreateJukeboxPlaylistAssignments < ActiveRecord::Migration[7.0]
  def change
    create_table :jukebox_playlist_assignments, id: :uuid do |t|
      t.uuid :jukebox_id, null: false
      t.uuid :playlist_id, null: false
      t.integer :weight, default: 1, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :jukebox_playlist_assignments, :jukebox_id, name: 'idx_jpa_jukebox_id'
    add_index :jukebox_playlist_assignments, :playlist_id, name: 'idx_jpa_playlist_id'
    add_index :jukebox_playlist_assignments, [:jukebox_id, :playlist_id], unique: true, name: 'idx_jpa_unique_assignment'
    add_index :jukebox_playlist_assignments, [:jukebox_id, :enabled], name: 'idx_jpa_jukebox_enabled'

    add_foreign_key :jukebox_playlist_assignments, :jukeboxes, column: :jukebox_id, on_delete: :cascade
    add_foreign_key :jukebox_playlist_assignments, :playlists, column: :playlist_id, on_delete: :cascade
  end
end
