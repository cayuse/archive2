require "test_helper"

class AudioFileProcessingJobTest < ActiveJob::TestCase
  setup do
    @user = users(:admin)
  end

  # A song with a (fake) audio file attached, waiting to be processed.
  def song_with_audio(title: "Test Song", processing_status: "pending", **attrs)
    song = Song.create!(title: title, user: @user, processing_status: processing_status, **attrs)
    song.audio_file.attach(io: StringIO.new("fake audio content"), filename: "test.mp3", content_type: "audio/mpeg")
    song
  end

  # Run the job with the file reader (AudioFileProcessor) reporting +metadata+. The job loads its
  # own copy of the song, so the stub has to sit below the model, not on a song instance.
  def process(song, metadata)
    processor = Struct.new(:metadata) { def process = metadata }.new(metadata)
    AudioFileProcessor.stub :new, processor do
      AudioFileProcessingJob.perform_now(song.id)
    end
    song.reload
  end

  test "fills the song in from the file's tags and completes it" do
    song = song_with_audio
    process(song, title: "Extracted Title", artist: "Extracted Artist", album: "Extracted Album", genre: "Blues",
                  track_number: 1, duration: 180, file_format: "mp3", file_size: 1024)

    assert_equal "completed", song.processing_status
    assert_nil song.processing_error
    assert_equal "Extracted Title", song.title
    assert_equal "Extracted Artist", song.artist.name
    assert_equal "Extracted Album", song.album.title
    assert_equal "Blues", song.genre.name
    assert_equal 1, song.track_number
    assert_equal 180, song.duration
    assert_equal "mp3", song.file_format
    assert_equal 1024, song.file_size
  end

  test "creates the artist, album and genre the tags name" do
    song = song_with_audio
    assert_difference [ "Artist.count", "Album.count", "Genre.count" ], 1 do
      process(song, title: "Extracted Title", artist: "Extracted Artist", album: "Extracted Album", genre: "Blues")
    end
  end

  test "reuses an artist, album and genre that already exist" do
    song = song_with_audio
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count" ] do
      process(song, title: "Extracted Title", artist: "Test Artist", album: "Test Album", genre: "Rock")
    end
    assert_equal artists(:one), song.artist
    assert_equal albums(:one), song.album
    assert_equal genres(:one), song.genre
  end

  test "tags replace what the song already had" do
    song = song_with_audio(title: "Typed Title", artist: artists(:one))
    process(song, title: "Extracted Title", artist: "Another Artist")
    assert_equal "Extracted Title", song.title
    assert_equal artists(:two), song.artist
  end

  test "a title and artist are enough to complete, with no album or genre" do
    song = song_with_audio
    process(song, title: "Extracted Title", artist: "Extracted Artist", file_format: "mp3", file_size: 1024)
    assert_equal "completed", song.processing_status
    assert_nil song.album
    assert_nil song.genre
  end

  test "the song's own title counts when the tags only give an artist" do
    song = song_with_audio(title: "Typed Title")
    process(song, artist: "Extracted Artist")
    assert_equal "completed", song.processing_status
    assert_equal "Typed Title", song.title
  end

  test "without an artist the song needs review, and no placeholder artist, album or genre is made" do
    song = song_with_audio
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count" ] do
      process(song, title: "Extracted Title", file_format: "mp3", file_size: 1024)
    end
    assert_equal "needs_review", song.processing_status
    assert_equal "Extracted Title", song.title
    assert_nil song.artist
    assert_nil song.album
    assert_nil song.genre
  end

  test "a file with no tags at all needs review" do
    song = song_with_audio(title: "")
    process(song, file_format: "mp3", file_size: 1024, title: nil, artist: nil, album: nil, genre: nil,
                  track_number: nil, duration: nil)
    assert_equal "needs_review", song.processing_status
    assert_equal "", song.title
    assert_equal "mp3", song.file_format
  end

  test "a file the real processor can read nothing from needs review" do
    song = song_with_audio(title: "")
    AudioFileProcessingJob.perform_now(song.id)
    song.reload
    assert_equal "needs_review", song.processing_status
    assert_nil song.processing_error
    assert_equal "mp3", song.file_format
    assert_equal "fake audio content".bytesize, song.file_size
  end

  test "a processing error fails the song and records why" do
    song = song_with_audio
    process(song, error: "Test error")
    assert_equal "failed", song.processing_status
    assert_equal "Test error", song.processing_error
    assert_equal "Test Song", song.title
  end

  test "finding no metadata in the filename is not a failure" do
    song = song_with_audio
    process(song, error: "No metadata found in filename")
    assert_equal "needs_review", song.processing_status
    assert_nil song.processing_error
  end

  test "an earlier error is cleared when processing succeeds" do
    song = song_with_audio(processing_status: "failed", processing_error: "old trouble")
    process(song, title: "Extracted Title", artist: "Extracted Artist")
    assert_equal "completed", song.processing_status
    assert_nil song.processing_error
  end

  test "skips a song with no audio file" do
    song = Song.create!(title: "Test Song", user: @user, processing_status: "pending")
    assert_no_changes -> { song.reload.attributes } do
      AudioFileProcessingJob.perform_now(song.id)
    end
  end

  test "skips a song that is already processing or completed" do
    %w[processing completed].each do |status|
      song = song_with_audio(processing_status: status)
      assert_no_changes -> { song.reload.attributes }, "status #{status}" do
        process(song, title: "Extracted Title", artist: "Extracted Artist")
      end
    end
  end

  test "does nothing for a song that no longer exists" do
    assert_nothing_raised do
      AudioFileProcessingJob.perform_now(SecureRandom.uuid)
    end
  end
end
