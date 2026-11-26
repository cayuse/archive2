# The durable Station: a person's radio station as a thing of its own, separate from the node-local
# jukebox that happens to be playing it. It holds the recipe (seeds, tuning, linked playlists) and
# owns the feedback log (thumbs, skips, full plays), so what a station has learned travels with the
# station and not with the machine.
#
#   stations.parent_id / forked_at   a copy: reads the parent's log up to forked_at, then its own
#   stations.archived_at             deleted by its owner but still the parent of someone's copy
#   stations.implicit                the private station behind a party jukebox's radio fill
#   station_playlists                playlists linked by reference: "inspire" (sets the sound) or
#                                    "only" (stay inside them)
#   jukeboxes.station_id             the station a jukebox plays from
#   station_feedbacks.station_id     replaces jukebox_id (kept, emptied, for one release)
class CreateStations < ActiveRecord::Migration[8.0]
  class MJukebox < ActiveRecord::Base; self.table_name = "jukeboxes"; end
  class MStation < ActiveRecord::Base; self.table_name = "stations"; end

  def up
    create_table :stations, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.string :name, null: false
      t.boolean :name_edited, null: false, default: false
      t.boolean :permanent, null: false, default: false     # the first station ("My Station")
      t.boolean :implicit, null: false, default: false
      t.boolean :shared, null: false, default: false
      t.jsonb :settings, null: false, default: {}
      t.string :origin_archive
      t.uuid :parent_id
      t.datetime :forked_at
      t.datetime :archived_at
      t.string :recipe_digest
      t.timestamps
    end
    add_index :stations, :user_id
    add_index :stations, :parent_id
    add_index :stations, :recipe_digest
    add_foreign_key :stations, :users, on_delete: :cascade

    create_table :station_playlists, id: :uuid do |t|
      t.uuid :station_id, null: false
      t.uuid :playlist_id, null: false
      t.string :mode, null: false, default: "inspire"
      t.timestamps
    end
    add_index :station_playlists, [ :station_id, :playlist_id ], unique: true
    add_foreign_key :station_playlists, :stations, on_delete: :cascade
    add_foreign_key :station_playlists, :playlists, on_delete: :cascade

    add_column :jukeboxes, :station_id, :uuid
    add_index :jukeboxes, :station_id
    add_column :station_feedbacks, :station_id, :uuid
    add_index :station_feedbacks, [ :station_id, :created_at ]

    # Every jukebox that is a station, plays radio, or has feedback gets a Station; its tuning and
    # its feedback move there.
    node = select_value("SELECT value FROM system_settings WHERE key = 'archive_node_id'") rescue nil
    with_feedback = select_values("SELECT DISTINCT jukebox_id FROM station_feedbacks WHERE jukebox_id IS NOT NULL")
    MJukebox.reset_column_information
    MJukebox.find_each do |j|
      personal = j.session_id.to_s.start_with?("station-")
      next unless personal || j.fill_mode == "radio" || with_feedback.include?(j.id)
      first = j.session_id == "station-#{j.owner_id.to_s.delete('-').first(12)}"
      station = MStation.create!(user_id: j.owner_id, name: j.name, name_edited: true, permanent: personal && first,
                                 implicit: !personal, settings: j.radio_settings || {}, origin_archive: node,
                                 created_at: j.created_at, updated_at: Time.current)
      j.update_columns(station_id: station.id)
      execute "UPDATE station_feedbacks SET station_id = #{connection.quote(station.id)} WHERE jukebox_id = #{connection.quote(j.id)}"
    end
    # tired / never belong to the person, not to a station
    execute "UPDATE station_feedbacks SET station_id = NULL WHERE kind IN ('tired', 'never')"
    execute "UPDATE station_feedbacks SET jukebox_id = NULL"
    add_foreign_key :station_feedbacks, :stations, on_delete: :cascade
  end

  def down
    execute "UPDATE station_feedbacks f SET jukebox_id = j.id FROM jukeboxes j WHERE j.station_id = f.station_id AND f.station_id IS NOT NULL"
    execute "UPDATE jukeboxes j SET radio_settings = s.settings FROM stations s WHERE s.id = j.station_id"
    remove_column :station_feedbacks, :station_id
    remove_column :jukeboxes, :station_id
    drop_table :station_playlists
    drop_table :stations
  end
end
