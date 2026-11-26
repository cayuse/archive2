# When on, this jukebox is driven by the node's hidden server-side player task
# (OwnTone/station daemon) instead of the host's browser. The /player page then
# loads as a passive controller, so closing/reopening it never affects playback.
class AddServerPlaybackToJukeboxes < ActiveRecord::Migration[8.0]
  def change
    add_column :jukeboxes, :server_playback, :boolean, null: false, default: false
  end
end
