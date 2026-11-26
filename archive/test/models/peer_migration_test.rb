require "test_helper"

class PeerMigrationTest < ActiveSupport::TestCase
  class Probe < ActiveRecord::Migration[8.1]
    def up
      on_peers { add_column :playlists, :peer_probe, :string }
      once_on_peers { Playlist.reset_column_information; Playlist.update_all(peer_probe: "set once") if Playlist.column_names.include?("peer_probe") }
    end
  end

  def migrate_quietly
    ActiveRecord::Migration.suppress_messages { Probe.new.migrate(:up) }
    Playlist.reset_column_information
  end

  teardown do
    if Playlist.connection.column_exists?(:playlists, :peer_probe)
      Playlist.connection.remove_column(:playlists, :peer_probe)
    end
    Playlist.reset_column_information
  end

  test "with no peers both blocks simply run" do
    Playlist.create!(user: users(:admin), name: "Probe")
    PeerSync.stub(:mode, :standalone) { migrate_quietly }
    assert_includes Playlist.column_names, "peer_probe"
    assert_equal [ "set once" ], Playlist.distinct.pluck(:peer_probe)
  end

  test "on the schema primary the schema change goes to every peer through the stream" do
    sent = nil
    PeerSync.stub(:mode, :primary) do
      PeerSync.stub(:replicate_ddl!, ->(statements) { sent = statements }) { migrate_quietly }
    end
    assert_not_includes Playlist.column_names, "peer_probe", "captured and undone here: replicate_ddl_command runs it"
    assert_equal 1, sent.size
    assert_match(/\AALTER TABLE "playlists" ADD "peer_probe"/, sent.first)
  end

  test "on other peers both blocks are skipped (the change and the rows arrive)" do
    PeerSync.stub(:mode, :replica) { migrate_quietly }
    assert_not_includes Playlist.column_names, "peer_probe"
  end

  test "the replicated command puts a new shared table in the replication set, and takes a dropped one out first" do
    command = PeerSync.ddl_command([ 'CREATE TABLE "playlists" ("id" uuid)', 'DROP TABLE "songs"', 'CREATE TABLE "jukeboxes" ("id" uuid)' ])
    assert command.start_with?("set local search_path = public;")
    assert_includes command, "CREATE TABLE \"playlists\" (\"id\" uuid);\nselect pglogical.replication_set_add_table('archive_shared', 'public.playlists', false);"
    assert_includes command, "select pglogical.replication_set_remove_table('archive_shared', 'public.songs');\nDROP TABLE \"songs\";"
    assert_not_includes command, "public.jukeboxes", "a local table is not replicated"
  end
end
