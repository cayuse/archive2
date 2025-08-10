class AddIsPublicToJukeboxPlaylists < ActiveRecord::Migration[8.0]
  def change
    add_column :jukebox_playlists, :is_public, :boolean, default: true, null: false
    add_index :jukebox_playlists, :is_public
  end
end


