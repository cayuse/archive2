require "test_helper"

class IntakeProcessorTest < ActiveSupport::TestCase
  RECORDING = "11111111-1111-4111-8111-111111111111".freeze
  RELEASE = "22222222-2222-4222-8222-222222222222".freeze
  ARTIST = "55555555-5555-4555-8555-555555555555".freeze

  setup do
    @user = users(:moderator)
    @batch = IntakeBatch.create!(user: @user, name: "test drop")
  end

  teardown { [ @batch.incoming_dir, @batch.work_dir, @batch.originals_dir ].each { |d| FileUtils.rm_rf(d) } }

  def drop(relative_path, source = file_fixture("tagged.mp3"))
    File.open(source, "rb") { |io| @batch.receive!(io, relative_path) }
  end

  def process(mirror: nil)
    @batch.finish_upload!
    IntakeProcessor.new(@batch, mirror: mirror, log: Logger.new(IO::NULL)).run
    @batch.reload.items.index_by(&:relative_path)
  end

  test "a folder: the music is added, everything else is set aside and listed" do
    drop("Album/01 song.mp3")
    drop("Album/info.nfo", file_fixture("test.txt"))
    drop("Album/cover.jpg", file_fixture("test.txt"))
    drop("Album/renamed text.mp3", file_fixture("test.txt"))
    items = process

    assert_equal "done", @batch.status
    assert_nil @batch.error
    assert_equal({ "imported" => 1, "rejected" => 3 }, @batch.counts)
    assert_equal "Not audio (nfo)", items["Album/info.nfo"].message
    assert_match "Not playable audio", items["Album/renamed text.mp3"].message

    song = items["Album/01 song.mp3"].song
    assert_equal "tags", items["Album/01 song.mp3"].identified
    assert_equal [ "Fixture Song", "Fixture-Artist", "Fixture_Album", 7, "completed" ],
                 [ song.title, song.artist.name, song.album.title, song.track_number, song.processing_status ]
    assert_equal [ @user, "01 song.mp3", "mp3" ], [ song.user, song.original_filename, song.file_format ]
    assert song.audio_file.attached?
    assert_equal "Fixture Song", song.file_tag.title
    assert_equal song.audio_file.checksum, song.file_tag.blob_checksum
    assert_includes Song.awaiting_analysis, song

    assert File.exist?(@batch.originals_dir.join("Album/01 song.mp3")), "the untouched original is kept"
    assert_not File.exist?(@batch.work_dir), "nothing is left behind"
    assert_not File.exist?(@batch.incoming_dir)
  end

  test "the same file dropped again is a duplicate, also after its tags were rewritten" do
    drop("first.mp3")
    first = process["first.mp3"].song
    assert_not_equal Digest::MD5.file(file_fixture("tagged.mp3")).base64digest, first.audio_file.checksum, "tags were rewritten"

    @batch = IntakeBatch.create!(user: @user, name: "again")
    drop("second copy.mp3")
    assert_no_difference "Song.count" do
      item = process["second copy.mp3"]
      assert_equal [ "duplicate", first ], [ item.status, item.song ]
    end
  end

  test "an archive is unpacked; links and paths that climb out of it are not followed" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/Rip")
      FileUtils.cp(file_fixture("tagged.mp3"), "#{dir}/Rip/02 track.mp3")
      File.write("#{dir}/Rip/rip.sfv", "junk")
      File.symlink("/etc/passwd", "#{dir}/Rip/passwd.mp3")
      assert system("tar", "-cf", "#{dir}/rip.tar", "-C", dir, "Rip")
      drop("rip.tar", "#{dir}/rip.tar")
    end
    items = process

    assert_equal "expanded", items["rip.tar"].status
    assert_equal "imported", items["rip.unpacked/Rip/02 track.mp3"].status, items.transform_values { |i| [ i.status, i.message ] }.inspect
    assert_equal "rejected", items["rip.unpacked/Rip/rip.sfv"].status
    assert_nil items["rip.unpacked/Rip/passwd.mp3"], "a link is dropped, not read"
    assert File.exist?(@batch.originals_dir.join("rip.tar"))
  end

  test "something that only claims to be an archive is set aside" do
    drop("broken.zip", file_fixture("test.txt"))
    item = process["broken.zip"]
    assert_equal "rejected", item.status
    assert_match(/\AArchive cannot be read/, item.message)
  end

  test "a file MusicBrainz knows is filed and tagged by MusicBrainz, and its release is not added twice" do
    match = { "title" => "The Real Title", "artist" => "The Real Artist", "album" => "The Real Album", "album_artist" => "The Real Artist",
              "track_number" => 2, "track_total" => 10, "date_raw" => "2001-02-03", "year" => 2001,
              "musicbrainz_recording_id" => RECORDING, "musicbrainz_release_id" => RELEASE, "musicbrainz_artist_ids" => [ ARTIST ],
              "musicbrainz_album_artist_ids" => [ ARTIST ], "match" => { "method" => "album", "score" => 1.0 } }
    matcher = Object.new
    matcher.define_singleton_method(:match) { |entries| entries.to_h { |e| [ e[:id], match ] } }
    mirror = Object.new
    def mirror.close = nil
    def mirror.artist(_gid) = nil
    def mirror.release(_gid) = nil
    def mirror.recording(_gid) = nil

    MusicbrainzMatcher.stub :new, matcher do
      drop("x/a.mp3")
      item = process(mirror: mirror)["x/a.mp3"]
      song = item.song
      assert_equal [ "imported", "album" ], [ item.status, item.identified ]
      assert_equal [ "The Real Title", "The Real Artist", "The Real Album", 2, RECORDING ],
                   [ song.title, song.artist.name, song.album.title, song.track_number, song.musicbrainz_recording_id ]
      assert_equal [ RELEASE, 2001, 10 ], [ song.album.musicbrainz_release_id, song.album.release_year, song.album.total_tracks ]
      assert_equal "Test", song.genre.name, "what MusicBrainz does not describe stays as the file had it"
      song.audio_file.blob.open do |stored|
        written = TagScanner.scan(stored.path)
        assert_equal [ "The Real Title", "The Real Album", RELEASE, "2001-02-03" ], written.values_at("title", "album", "musicbrainz_release_id", "date_raw")
      end

      # a different rip of the same track of the same release
      Dir.mktmpdir do |dir|
        assert system("ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=220:duration=1", "-b:a", "32k", "#{dir}/other.mp3")
        @batch = IntakeBatch.create!(user: @user, name: "other rip")
        drop("y/other.mp3", "#{dir}/other.mp3")
      end
      assert_no_difference "Song.count" do
        again = process(mirror: mirror)["y/other.mp3"]
        assert_equal [ "duplicate", song ], [ again.status, again.song ]
      end
    end
  end

  test "an interrupted drop is finished on the next run without adding anything twice" do
    drop("a.mp3")
    @batch.finish_upload!
    FileUtils.mkdir_p(@batch.work_dir)
    FileUtils.cp(file_fixture("test.txt"), @batch.work_dir.join("left over.nfo"))   # as if a first run had got part way
    IntakeItem.create!(intake_batch: @batch, relative_path: "left over.nfo", status: "rejected", message: "Not audio (nfo)")
    assert_equal({ "imported" => 1, "rejected" => 1 }, (process; @batch.counts))
  end

  test "paths from the browser cannot leave the drop" do
    assert_equal "a/b.mp3", Intake.safe_path("../../a/./b.mp3")
    assert_equal "etc/passwd", Intake.safe_path("/etc/passwd")
    assert_equal "C:/Music/x.mp3", Intake.safe_path("C:\\Music\\..\\x.mp3")
    assert_raises(ArgumentError) { Intake.safe_path("../..") }
    target = drop("../../../escape.mp3")
    assert target.to_s.start_with?(@batch.incoming_dir.to_s + "/")
  end

  test "originals are cleared after the keeping period" do
    Dir.mktmpdir do |root|   # its own root: pruning must not touch the drops of tests running alongside
      Intake.stub :root, Pathname.new(root) do
        FileUtils.mkdir_p(@batch.originals_dir)
        assert_equal 0, Intake.prune_originals
        assert_equal 1, Intake.prune_originals(now: 31.days.from_now)
        assert_not File.exist?(@batch.originals_dir)
      end
    end
  end
end
