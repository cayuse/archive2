# Which users may start local playback on which archive node. A thin has_many
# :through (not a bare HABTM) so it carries a UUID PK and timestamps -> safe to
# replicate between peers later.
class CreatePlaybackGrants < ActiveRecord::Migration[8.0]
  def change
    create_table :playback_grants, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :archive_node, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.timestamps
    end
    add_index :playback_grants, [ :user_id, :archive_node_id ], unique: true
  end
end
