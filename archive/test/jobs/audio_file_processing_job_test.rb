require "test_helper"

# The job reads the stored file's tags and hands them to LibraryImporter (whose rules have their
# own tests). Here: that the wiring works on a real file, and what happens around it.
class AudioFileProcessingJobTest < ActiveJob::TestCase
  setup do
    @user = users(:admin)
  end

  def song_with(file, processing_status: "pending", **attrs)
    song = Song.create!(title: "Uploaded", user: @user, processing_status: processing_status, **attrs)
    song.audio_file.attach(io: File.open(file_fixture(file)), filename: file, content_type: "audio/mpeg")
    song
  end

  def process(song)
    AudioFileProcessingJob.perform_now(song.id)
    song.reload
  end

  test "files the song by its tags, unchanged, and keeps a record of them" do
    song = process(song_with("tagged.mp3"))
    assert_equal [ "Fixture Song", "Fixture-Artist", "Fixture_Album", "Test", 7, "completed" ],
                 [ song.title, song.artist.name, song.album.title, song.genre.name, song.track_number, song.processing_status ]
    assert_equal song.artist, song.album.artist
    assert_equal [ "Fixture Song", song.audio_file.checksum ], [ song.file_tag.title, song.file_tag.blob_checksum ]
    assert_equal "mp3", song.file_format
  end

  test "processing again adds nothing" do
    song = process(song_with("tagged.mp3"))
    song.update_columns(processing_status: "needs_review")
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count", "SongFileTag.count" ] do
      process(song)
    end
  end

  test "a file that cannot be read fails the song and says why; a later success clears it" do
    song = process(song_with("test.txt"))
    assert_equal "failed", song.processing_status
    assert song.processing_error.present?
    assert_nil song.artist

    song.update_columns(processing_status: "pending")
    TagScanner.stub :scan, { "title" => "Now Readable", "artist" => "Someone", "musicbrainz_artist_ids" => [] } do
      process(song)
    end
    assert_equal [ "completed", nil, "Now Readable" ], [ song.processing_status, song.processing_error, song.title ]
  end

  test "a file with no tags needs review and creates no placeholder rows" do
    song = song_with("tagged.mp3")
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count" ] do
      TagScanner.stub(:scan, { "musicbrainz_artist_ids" => [] }) { process(song) }
    end
    assert_equal [ "needs_review", "Uploaded" ], [ song.processing_status, song.title ]
  end

  test "skips a song with no audio file, one already processing or completed, and one that is gone" do
    bare = Song.create!(title: "No file", user: @user, processing_status: "pending")
    AudioFileProcessingJob.perform_now(bare.id)
    assert_equal "pending", bare.reload.processing_status

    %w[processing completed].each do |status|
      song = song_with("tagged.mp3", processing_status: status)
      assert_equal "Uploaded", process(song).title
    end
    assert_nothing_raised { AudioFileProcessingJob.perform_now(SecureRandom.uuid) }
  end
end
