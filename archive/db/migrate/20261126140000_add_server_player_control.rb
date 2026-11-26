# Server-side playback, end to end: the archive holds the desired state and the node's player
# daemon (station.py) follows it.
#   jukeboxes.server_transport   what the on-air jukebox should be doing: play / pause / stop
#   archive_nodes.player_token   secret the node's daemon presents (X-Node-Token)
#   archive_nodes.player_commands one-shot commands for the daemon (skip, volume, output, retune)
#   archive_nodes.player_state    what the daemon last reported (outputs, volume, error)
class AddServerPlayerControl < ActiveRecord::Migration[8.0]
  def change
    add_column :jukeboxes, :server_transport, :string, null: false, default: "stop"
    add_column :archive_nodes, :player_token, :string
    add_column :archive_nodes, :player_commands, :jsonb, null: false, default: []
    add_column :archive_nodes, :player_command_seq, :integer, null: false, default: 0
    add_column :archive_nodes, :player_state, :jsonb, null: false, default: {}
    add_column :archive_nodes, :player_seen_at, :datetime
    add_index :archive_nodes, :player_token, unique: true
  end
end
