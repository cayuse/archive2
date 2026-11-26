require "test_helper"

class PeerSyncTest < ActiveSupport::TestCase
  test "every table is either shared with peers or kept local (classify new tables in PeerSync)" do
    assert_empty PeerSync.unclassified_tables
    assert_empty PeerSync::SHARED_TABLES & PeerSync::LOCAL_TABLES
    assert_empty (PeerSync::SHARED_TABLES + PeerSync::LOCAL_TABLES) - ActiveRecord::Base.connection.tables, "a listed table no longer exists"
  end

  test "rows unique by a natural key get the same id on every peer" do
    rock = Genre.create!(name: "Peer Rock")
    assert_equal NaturalId.for(Genre, "Peer Rock"), rock.id
    rock.destroy
    assert_equal rock.id, Genre.create!(name: "Peer Rock").id, "created again elsewhere: same id"

    mbid = "a74b1b7f-71a5-4011-9441-d0b5e4122711"
    assert_equal NaturalId.for(Artist, mbid), Artist.create!(name: "Radiohead", musicbrainz_id: mbid).id
    release = "b1392450-e666-3926-a536-22c65f834433"
    assert_equal NaturalId.for(Album, release), Album.create!(title: "OK Computer", musicbrainz_release_id: release).id
  end

  test "rows without a natural key keep random ids" do
    a, b = Artist.create!(name: "No Id"), Artist.create!(name: "No Id")
    assert_not_equal a.id, b.id
    assert_not_equal NaturalId.for(Artist, ""), a.id
  end

  test "a peer's node id comes from its deploy config when set" do
    ENV["ARCHIVE_NODE_ID"] = "peer-test"
    assert_equal "peer-test", SystemSetting.archive_node_id
  ensure
    ENV.delete("ARCHIVE_NODE_ID")
  end
end
