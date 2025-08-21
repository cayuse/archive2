class CreateJukeboxSelectedPlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :jukebox_selected_playlists do |t|
      t.uuid :playlist_id, null: false  # archive playlists.id (UUID)
      t.timestamps
      t.index :playlist_id, unique: true
    end
  end
end


