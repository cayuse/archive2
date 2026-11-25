# What a listener told a station about a song. Replaces song_ratings (one global thumb per user):
# thumbs now belong to the station they were given on, and there are more signals than up/down.
#
#   up / down   thumbs, scoped to jukebox_id (NULL = the user's own thumbs outside any station)
#   tired       "sick of this track": shelved for every station of that user until expires_at
#   never       never play this for me, anywhere
#   skip        skipped while playing (position = seconds in)
#   finished    played to the end
class CreateStationFeedbacks < ActiveRecord::Migration[8.0]
  def up
    create_table :station_feedbacks, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.references :jukebox, null: true, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :kind, null: false
      t.float :position
      t.datetime :expires_at

      t.timestamps
    end
    add_index :station_feedbacks, [ :jukebox_id, :kind, :song_id ]
    add_index :station_feedbacks, [ :user_id, :kind, :song_id ]

    # Carry the old thumbs over: onto the owner's first station when they have one. song_ratings
    # itself is left in place (unused) so this migration can be rolled back without losing them.
    execute <<~SQL
      INSERT INTO station_feedbacks (user_id, jukebox_id, song_id, kind, created_at, updated_at)
      SELECT r.user_id,
             (SELECT j.id FROM jukeboxes j
               WHERE j.owner_id = r.user_id AND j.session_id LIKE 'station-%'
               ORDER BY j.created_at LIMIT 1),
             r.song_id,
             CASE WHEN r.value > 0 THEN 'up' ELSE 'down' END,
             r.created_at, r.updated_at
        FROM song_ratings r
    SQL
  end

  def down
    drop_table :station_feedbacks
  end
end
