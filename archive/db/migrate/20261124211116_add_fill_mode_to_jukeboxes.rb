class AddFillModeToJukeboxes < ActiveRecord::Migration[8.0]
  def change
    # how the queue is topped up: "random" from assigned playlists, or "radio" (songs that sound like what is playing)
    add_column :jukeboxes, :fill_mode, :string, null: false, default: "random"
  end
end
