# Two or more archives ("peers") kept in step, both ways, by pglogical (Postgres logical replication
# with conflict resolution). The runbook is docs/PEERS.md; this module is what it runs.
#
# Every table is either SHARED (replicated to and from every peer) or LOCAL (each peer's own). A
# test fails when a table is in neither list, so a new migration cannot quietly leave a table out.
#
# Conflicts (the same row changed on two peers before they heard from each other) are settled by
# pglogical.conflict_resolution = last_update_wins: the most recent commit wins, on every peer.
# Natural keys that are unique (genre name, artist / release MusicBrainz id) get ids derived from
# the key (NaturalId), so two peers that create "the same" row create the same id, and the clash is
# settled on that one row instead of one peer's row being replaced under another id.
module PeerSync
  SET = "archive_shared".freeze

  SHARED_TABLES = %w[
    songs artists albums genres albums_genres artists_genres song_artist_credits song_file_tags
    song_audio_features song_embeddings song_neighbors genre_affinities
    active_storage_blobs active_storage_attachments active_storage_variant_records
    users playlists playlists_songs stations station_playlists station_feedbacks
    themes theme_assets theme_settings
  ].freeze

  # What happens here stays here: live jukebox state, this node's identity and settings, its Drop
  # Box, its keys, its speakers. Rails' own bookkeeping too: every peer runs its own migrations.
  LOCAL_TABLES = %w[
    jukeboxes ajb_queue_items ajb_played_songs jukebox_playlist_assignments
    system_settings archive_nodes playback_grants service_keys intake_batches intake_items
    schema_migrations ar_internal_metadata
  ].freeze

  module_function

  def conn = ActiveRecord::Base.connection
  def quote(value) = conn.quote(value)

  def unclassified_tables
    conn.tables.sort - SHARED_TABLES - LOCAL_TABLES
  end

  def installed?
    conn.select_value("select 1 from pg_extension where extname = 'pglogical'").present?
  end

  def node_name
    installed? ? conn.select_value("select node_name from pglogical.local_node join pglogical.node using (node_id)") : nil
  rescue ActiveRecord::StatementInvalid
    nil
  end

  # This database becomes a pglogical node publishing the shared tables. Safe to run again: it only
  # adds what is missing (run it after every migration that adds a shared table).
  def setup_node!(name:, dsn:)
    conn.execute("create extension if not exists pglogical")
    if node_name.nil?
      conn.execute("select pglogical.create_node(node_name := #{quote(name)}, dsn := #{quote(dsn)})")
    elsif node_name != name
      raise "this database is already node #{node_name.inspect}, not #{name.inspect}"
    end
    unless conn.select_value("select 1 from pglogical.replication_set where set_name = #{quote(SET)}")
      # inserts, updates and deletes replicate; TRUNCATE does not (one bad truncate must not empty every peer)
      conn.execute("select pglogical.create_replication_set(#{quote(SET)}, true, true, true, false)")
    end
    in_set = conn.select_values("select set_reloid::regclass::text from pglogical.replication_set_table t " \
                                "join pglogical.replication_set s using (set_id) where s.set_name = #{quote(SET)}")
    added = (SHARED_TABLES & conn.tables) - in_set.map { |t| t.delete_prefix("public.") }
    added.each do |table|
      # synchronize_data: subscribers that already exist copy the rows of a newly added table
      conn.execute("select pglogical.replication_set_add_table(#{quote(SET)}, #{quote(table)}::regclass, true)")
    end
    added
  end

  # Start receiving the shared tables from another peer. copy: take a full copy of its rows first
  # (only for a peer that starts empty; never in both directions).
  def subscribe!(name:, provider_dsn:, copy:)
    conn.execute(<<~SQL)
      select pglogical.create_subscription(
        subscription_name := #{quote(name)}, provider_dsn := #{quote(provider_dsn)},
        replication_sets := array[#{quote(SET)}], synchronize_structure := false,
        synchronize_data := #{copy ? 'true' : 'false'}, forward_origins := '{}')
    SQL
  end

  def unsubscribe!(name)
    conn.execute("select pglogical.drop_subscription(#{quote(name)})")
  end

  def subscriptions
    return [] unless installed?
    conn.select_all("select subscription_name, status, provider_node, slot_name from pglogical.show_subscription_status()").to_a
  end

  # Tables of a subscription still copying their initial rows (empty when the copy is done).
  def syncing_tables(subscription)
    conn.select_values("select relname from pglogical.local_sync_status s join pg_class c on c.oid = s.sync_relid " \
                       "join pglogical.subscription sub on sub.sub_id = s.sync_subid " \
                       "where sub.sub_name = #{quote(subscription)} and s.sync_status <> 'r'")
  end

  # Peers that read from this one, and how far behind they are (WAL this node keeps for them).
  def outgoing
    conn.select_all(<<~SQL).to_a
      select slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) as behind,
             wal_status
      from pg_replication_slots where plugin = 'pglogical_output'
    SQL
  end

  # References in the shared tables that point at nothing. Replication applies rows without
  # checking foreign keys, so a clash or an out-of-order delete can leave these; the app copes
  # with a missing artist or album, but they are worth knowing about.
  DANGLING = {
    "songs.artist_id" => "select count(*) from songs s where s.artist_id is not null and not exists (select 1 from artists a where a.id = s.artist_id)",
    "songs.album_id" => "select count(*) from songs s where s.album_id is not null and not exists (select 1 from albums a where a.id = s.album_id)",
    "songs.genre_id" => "select count(*) from songs s where s.genre_id is not null and not exists (select 1 from genres g where g.id = s.genre_id)",
    "albums.artist_id" => "select count(*) from albums b where b.artist_id is not null and not exists (select 1 from artists a where a.id = b.artist_id)",
    "attachments.blob_id" => "select count(*) from active_storage_attachments t where not exists (select 1 from active_storage_blobs b where b.id = t.blob_id)",
    "song_artist_credits" => "select count(*) from song_artist_credits c where not exists (select 1 from songs s where s.id = c.song_id) or not exists (select 1 from artists a where a.id = c.artist_id)",
    "playlists_songs" => "select count(*) from playlists_songs p where not exists (select 1 from songs s where s.id = p.song_id)",
    "station_feedbacks" => "select count(*) from station_feedbacks f where f.station_id is not null and not exists (select 1 from stations s where s.id = f.station_id)"
  }.freeze

  def dangling
    DANGLING.transform_values { |sql| conn.select_value(sql).to_i }.select { |_, n| n.positive? }
  end
end
