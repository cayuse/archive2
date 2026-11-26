# Migrations once peers are mirrored (docs/PEERS.md, "Continued development").
#
#   def up
#     on_peers { add_column :playlists, :mood, :string }       # schema of SHARED tables
#     once_on_peers { Playlist.update_all(mood: "calm") }       # data in SHARED tables
#     add_column :jukeboxes, :lights, :boolean                  # LOCAL tables: as usual, on every node
#   end
#
# Why: every node runs every migration (schema_migrations is local), but a shared table's schema
# must change on all nodes at the same point in the replication stream. A node that gets ahead
# stops the others' replication ("unknown column"), and a node that is behind and still writing
# sends whole rows that undo newer changes (both seen on the gameforge test pair, 2026-11-26).
# So:
#   on_peers       on the schema primary (PEER_SCHEMA_PRIMARY=true: bigballs) the block's SQL is
#                  captured and sent with pglogical.replicate_ddl_command: it runs there and on every
#                  other node at that point of the stream; creating or dropping a shared table also
#                  puts it in / takes it out of every node's replication set. On other peers the
#                  block is skipped (the change arrives). Where there are no peers (development,
#                  tests, staging, a lone archive) it simply runs.
#   once_on_peers  runs on the schema primary or where there are no peers; skipped on other peers
#                  (the rows arrive). Run on every node it would make duplicates or double-apply.
module PeerMigration
  def on_peers(&block)
    case PeerSync.mode
    when :standalone then yield
    when :replica then say "on_peers: skipped here, arrives from the schema primary"
    when :primary
      statements = PeerSync.capture_ddl(connection, &block)
      say "on_peers: #{statements.size} statements to every peer"
      PeerSync.replicate_ddl!(statements)
    end
  end

  def once_on_peers
    if PeerSync.mode == :replica
      say "once_on_peers: skipped here, the schema primary's rows arrive"
    else
      yield
    end
  end
end
