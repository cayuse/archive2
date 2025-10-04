class AddPlaybackFieldsToJukeboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :jukeboxes, :current_song_id, :uuid
    add_column :jukeboxes, :current_position, :decimal, precision: 10, scale: 3, default: 0
    add_column :jukeboxes, :is_playing, :boolean, default: false
    add_column :jukeboxes, :volume, :decimal, precision: 3, scale: 2, default: 0.8
    add_column :jukeboxes, :last_status_update, :datetime
    
    add_index :jukeboxes, :current_song_id
    add_foreign_key :jukeboxes, :songs, column: :current_song_id, on_delete: :nullify
  end
end
