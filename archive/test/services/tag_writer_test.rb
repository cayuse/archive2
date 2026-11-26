require "test_helper"

# Round trip per format: a file with a ripper's junk tags is rewritten, read back with the scanner,
# and must carry exactly what was asked for, with the audio unchanged.
class TagWriterTest < ActiveSupport::TestCase
  WANTED = {
    "title" => "Froggy Went a Courtin’ (intro)", "artist" => "Ella Langley feat. Someone", "album" => "Dandelion",
    "album_artist" => "Ella Langley", "genre" => "Country", "track_number" => 3, "track_total" => 18, "disc_number" => 1,
    "disc_total" => 2, "date_raw" => "2026-04-10", "original_date_raw" => "2026", "label" => "SAWGOD", "barcode" => "0196588",
    "media" => "CD", "release_type" => "album; live", "release_status" => "official", "release_country" => "US",
    "artist_sort" => "Langley, Ella", "compilation" => true,
    "musicbrainz_recording_id" => "11111111-1111-4111-8111-111111111111", "musicbrainz_release_id" => "22222222-2222-4222-8222-222222222222",
    "musicbrainz_release_group_id" => "33333333-3333-4333-8333-333333333333",
    "musicbrainz_release_track_id" => "44444444-4444-4444-8444-444444444444",
    "musicbrainz_artist_ids" => %w[55555555-5555-4555-8555-555555555555 66666666-6666-4666-8666-666666666666],
    "musicbrainz_album_artist_ids" => %w[55555555-5555-4555-8555-555555555555]
  }.freeze

  def make(ext, *codec)
    path = File.join(@dir, "song.#{ext}")
    ok = system("ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=330:duration=1", *codec,
                "-metadata", "title=old_title", "-metadata", "comment=ripped by JUNK", "-metadata", "RIPPING TOOL=junk",
                "-metadata", "album=old album", "-metadata", "composer=Old Composer", path)
    assert ok, "ffmpeg could not make a .#{ext} test file"
    path
  end

  setup { @dir = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@dir) }

  { "mp3" => %w[-b:a 32k], "flac" => [], "m4a" => %w[-c:a aac -b:a 32k], "ogg" => %w[-c:a libvorbis] }.each do |ext, codec|
    test "#{ext}: tags are replaced with the standard set and the audio is untouched" do
      path = make(ext, *codec)
      before = TagWriter.audio_digest(path)
      assert_equal :written, TagWriter.write(path, WANTED)
      assert_equal before, TagWriter.audio_digest(path)

      got = TagScanner.scan(path)
      assert_nil got["scan_error"]
      WANTED.each { |field, value| assert_equal value, got[field], "#{ext} #{field}" }
      assert_nil got["composer"], "a tag that was not asked for is gone"
      assert_no_match(/junk/i, got["raw_tags"].to_json)
      assert_not File.exist?("#{path}.before-tagging")
    end
  end

  test "an mp3 loses its ID3v1 block" do
    path = make("mp3", "-b:a", "32k", "-write_id3v1", "1")
    assert_equal "TAG", File.binread(path)[-128, 3]
    TagWriter.write(path, WANTED)
    assert_not_equal "TAG", File.binread(path)[-128, 3]
  end

  test "a format without a tag standard is left alone" do
    path = make("wav")
    bytes = File.binread(path)
    assert_equal :unsupported, TagWriter.write(path, WANTED)
    assert_equal bytes, File.binread(path)
  end

  test "a file that is not audio raises and is left as it was" do
    path = File.join(@dir, "notes.mp3")
    File.write(path, "not audio at all")
    assert_raises(TagWriter::Error) { TagWriter.write(path, WANTED) }
    assert_equal "not audio at all", File.read(path)
  end
end
