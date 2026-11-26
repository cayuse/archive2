require "test_helper"

class LibraryImporterTest < ActiveSupport::TestCase
  A1 = "11111111-1111-4111-8111-111111111111".freeze
  A2 = "22222222-2222-4222-8222-222222222222".freeze
  R1 = "33333333-3333-4333-8333-333333333333".freeze

  # Stands in for the MusicBrainz mirror.
  class FakeMirror
    def initialize(artists: {}, releases: {}, down: false) = (@artists, @releases, @down = artists, releases, down)
    def artist(gid) = @down ? raise(PG::ConnectionBad, "down") : @artists[gid]
    def release(gid) = @down ? raise(PG::ConnectionBad, "down") : @releases[gid]
    def recording(_gid) = @down ? raise(PG::ConnectionBad, "down") : nil
  end

  def import(tags = nil, song: nil, musicbrainz: nil, **bare)
    tags ||= bare.transform_keys(&:to_s)
    song ||= Song.create!(title: "upload", user: users(:admin), processing_status: "needs_review")
    LibraryImporter.new(song, { "musicbrainz_artist_ids" => [], "musicbrainz_album_artist_ids" => [] }.merge(tags), musicbrainz: musicbrainz).apply!
  end

  test "tag values come through unchanged, hyphens and underscores included" do
    song = import("title" => "1-2-8 (re_mix)", "artist" => "AC-DC", "album" => "Back_in-Black", "genre" => "Hip-Hop",
                  "track_number" => 3, "disc_number" => 2, "duration_seconds" => 201.6)
    assert_equal [ "1-2-8 (re_mix)", "AC-DC", "Back_in-Black", "Hip-Hop" ], [ song.title, song.artist.name, song.album.title, song.genre.name ]
    assert_equal [ 3, 2, 202, "completed" ], [ song.track_number, song.disc_number, song.duration, song.processing_status ]
    assert_equal song.artist, song.album.artist
  end

  test "two artists with an album of the same title get an album each" do
    a = import("title" => "One", "artist" => "First Band", "album" => "Greatest Hits")
    b = import("title" => "Two", "artist" => "Second Band", "album" => "Greatest Hits")
    c = import("title" => "Three", "artist" => "first band", "album" => "greatest hits")
    assert_not_equal a.album, b.album
    assert_equal a.album, c.album
    assert_equal a.artist, c.artist
  end

  test "songs sharing a MusicBrainz release id land on one album whatever their album tags say" do
    a = import("title" => "One", "artist" => "Band", "album" => "The Album", "musicbrainz_release_id" => R1)
    b = import("title" => "Two", "artist" => "Band", "album" => "The Album (Deluxe)", "musicbrainz_release_id" => R1)
    assert_equal a.album, b.album
    assert_equal "The Album", b.album.title
  end

  test "each MusicBrainz artist id becomes a credit, in order, named from MusicBrainz" do
    mirror = FakeMirror.new(artists: { A1 => { "gid" => A1, "name" => "Toby Keith", "sort_name" => "Keith, Toby", "type" => "Person" },
                                       A2 => { "gid" => A2, "name" => "Willie Nelson" } })
    song = import({ "title" => "Beer for My Horses", "artist" => "Toby Keith feat. Willie Nelson", "musicbrainz_artist_ids" => [ A1, A2 ] },
                  musicbrainz: mirror)
    assert_equal "Toby Keith", song.artist.name
    assert_equal "Keith, Toby", song.artist.sort_name
    assert_equal "Toby Keith feat. Willie Nelson", song.artist_credit
    assert_equal [ "Toby Keith", "Willie Nelson" ], song.song_artist_credits.map { |c| c.artist.name }
  end

  test "with MusicBrainz unreachable the import completes from the tags" do
    song = import({ "title" => "Song", "artist" => "Solo Act", "album" => "LP", "musicbrainz_artist_ids" => [ A1 ],
                    "musicbrainz_release_id" => R1 }, musicbrainz: FakeMirror.new(down: true))
    assert_equal "completed", song.processing_status
    assert_equal [ "Solo Act", A1 ], [ song.artist.name, song.artist.musicbrainz_id ]
    assert_equal R1, song.album.musicbrainz_release_id
  end

  test "a compilation with no album artist goes under Various Artists" do
    song = import("title" => "Hit", "artist" => "Someone", "album" => "Now 40", "compilation" => true)
    assert_equal "Various Artists", song.album.artist.name
    assert song.album.compilation
    assert_equal "Someone", song.artist.name
  end

  test "an album artist tag owns the album" do
    song = import("title" => "Duet", "artist" => "Guest Singer", "album" => "Host Album", "album_artist" => "Host", "year" => 1999,
                  "track_total" => 12, "label" => "Label")
    assert_equal "Host", song.album.artist.name
    assert_equal [ 1999, 12, "Label" ], [ song.album.release_year, song.album.total_tracks, song.album.label ]
  end

  test "genres match ignoring case and punctuation" do
    a = import("title" => "One", "artist" => "X", "genre" => "Hip-Hop")
    b = import("title" => "Two", "artist" => "X", "genre" => "hip hop")
    assert_equal a.genre, b.genre
  end

  test "a file with no tags needs review and creates no placeholder rows" do
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count" ] do
      song = import({})
      assert_equal "needs_review", song.processing_status
      assert_equal "upload", song.title
      assert_nil song.album
    end
  end

  test "importing the same tags twice adds nothing, and missing tags leave the database alone" do
    tags = { "title" => "Same", "artist" => "Same Artist", "album" => "Same Album", "genre" => "Rock", "musicbrainz_artist_ids" => [ A1 ] }
    song = import(tags)
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count", "SongArtistCredit.count" ] do
      import(tags, song: song)
    end
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count" ] do
      import(tags)   # another copy of the same song
    end
    genre = song.genre
    import({ "title" => "Renamed" }, song: song)
    assert_equal [ "Renamed", "Same Artist", genre ], [ song.title, song.artist.name, song.genre ]
  end

  test "a name held by exactly one MusicBrainz artist uses that artist" do
    known = Artist.create!(name: "Known Band", musicbrainz_id: A2)
    assert_equal known, import("title" => "T", "artist" => "known band").artist
  end

  test "the scanner reads a real file" do
    tags = TagScanner.scan(file_fixture("tagged.mp3"))
    assert_nil tags["scan_error"]
    assert_equal [ "Fixture Song", "Fixture-Artist", "Fixture_Album", 7 ], tags.values_at("title", "artist", "album", "track_number")
    assert_equal [], tags["musicbrainz_artist_ids"]
    assert_equal "scan_error", TagScanner.scan(file_fixture("test.txt")).compact.keys.grep(/error/).first
  end
end
