# An archive node a user might start local playback on: this one, and any peer
# (master or clone) that offers it. Node-agnostic and UUID-keyed so rows are safe
# to replicate between peers later; nothing here wires replication.
class CreateArchiveNodes < ActiveRecord::Migration[8.0]
  def change
    create_table :archive_nodes, id: :uuid do |t|
      t.string  :node_id, null: false          # matches system_settings 'archive_node_id'
      t.string  :name, null: false
      t.boolean :local_playback, null: false, default: false  # does this node offer local playback?
      t.string  :player_url                     # link to this node's player site (to edit the connection)
      t.string  :lan_cidr                       # what counts as "local" here; blank = any private range
      t.timestamps
    end
    add_index :archive_nodes, :node_id, unique: true
  end
end
