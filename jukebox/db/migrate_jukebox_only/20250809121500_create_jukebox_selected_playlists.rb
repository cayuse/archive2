class CreateJukeboxSelectedPlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :jukebox_selected_playlists do |t|
      t.bigint :playlist_id, null: false  # archive playlists.id
      t.timestamps
      t.index :playlist_id, unique: true
    end
  end
end


