require "test_helper"

class SongTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  AUDIO = "fake audio content".freeze

  setup do
    @user = users(:admin)
    @artist = artists(:one)
    @album = albums(:one)
    @genre = genres(:one)
  end

  def attach_audio(song, filename: "test.mp3", content_type: "audio/mpeg")
    song.audio_file.attach(io: StringIO.new(AUDIO), filename: filename, content_type: content_type)
    song
  end

  test "saves with a title, user, artist, album and genre" do
    song = Song.new(title: "Test Song", user: @user, artist: @artist, album: @album, genre: @genre)
    assert song.save
  end

  test "nothing is required by the model: an upload starts blank and is filled in later" do
    assert Song.new.valid?
  end

  test "saves with only a title, and with a blank one" do
    song = Song.new(title: "Test Song")
    assert song.save
    assert_nil song.user
    assert_nil song.artist
    assert Song.new(title: "").save
  end

  test "a title may be blank but not longer than 200 characters" do
    assert Song.new(title: "").valid?
    assert Song.new(title: "a" * 200).valid?
    song = Song.new(title: "a" * 201)
    assert_not song.valid?
    assert_includes song.errors[:title], "is too long (maximum is 200 characters)"
  end

  test "track number, duration and file size must be positive whole numbers when given" do
    %i[track_number duration file_size].each do |field|
      assert Song.new(field => 3).valid?, "#{field} 3"
      assert Song.new(field => nil).valid?, "#{field} nil"
      [ 0, -1, 1.5 ].each do |bad|
        song = Song.new(field => bad)
        assert_not song.valid?, "#{field} #{bad}"
        assert song.errors[field].any?
      end
    end
  end

  test "file format must be a supported one" do
    %w[mp3 m4a mp4 ogg flac wav aac].each { |format| assert Song.new(file_format: format).valid?, format }
    song = Song.new(file_format: "wma")
    assert_not song.valid?
    assert_includes song.errors[:file_format], "wma is not a supported format"
  end

  test "processing status must be a known one" do
    %w[pending processing completed failed needs_review new].each { |status| assert Song.new(processing_status: status).valid?, status }
    song = Song.new(processing_status: "bogus")
    assert_not song.valid?
    assert_includes song.errors[:processing_status], "bogus is not a valid status"
  end

  test "a new song has no processing status" do
    song = Song.new(title: "Test Song", user: @user)
    assert_nil song.processing_status
    assert_not song.processing_pending?
    assert_not song.processing_in_progress?
    assert_not song.processing_completed?
    assert_not song.processing_failed?
    assert_not song.needs_review?
  end

  test "each processing status has its predicate" do
    { "pending" => :processing_pending?, "processing" => :processing_in_progress?, "completed" => :processing_completed?,
      "failed" => :processing_failed?, "needs_review" => :needs_review? }.each do |status, predicate|
      song = Song.new(processing_status: status)
      assert song.public_send(predicate), "#{status} should be #{predicate}"
      others = %i[processing_pending? processing_in_progress? processing_completed? processing_failed? needs_review?] - [ predicate ]
      others.each { |other| assert_not song.public_send(other), "#{status} should not be #{other}" }
    end
  end

  test "processing status scopes pick out their songs" do
    statuses = %w[pending processing completed failed needs_review]
    made = statuses.index_with { |status| Song.create!(title: "Status #{status}", processing_status: status) }
    assert_includes Song.pending_processing, made["pending"]
    assert_includes Song.processing, made["processing"]
    assert_includes Song.completed, made["completed"]
    assert_includes Song.failed, made["failed"]
    assert_includes Song.needs_review, made["needs_review"]
    assert_equal [ "pending" ], Song.pending_processing.distinct.pluck(:processing_status)
    assert_equal [ "completed" ], Song.completed.distinct.pluck(:processing_status)
    assert_includes Song.completed, songs(:one)
    assert_includes Song.needs_review, songs(:two)
  end

  test "metadata is complete with a title and an artist" do
    song = Song.new
    assert_not song.has_complete_metadata?
    assert_not song.has_partial_metadata?
    assert song.has_no_metadata?

    song.title = "Test Song"
    assert_not song.has_complete_metadata?
    assert song.has_partial_metadata?
    assert_not song.has_no_metadata?

    song.artist = @artist
    assert song.has_complete_metadata?
    assert song.has_partial_metadata?
    assert_not song.has_no_metadata?
  end

  test "an album or genre alone is partial metadata" do
    assert Song.new(album: @album).has_partial_metadata?
    assert Song.new(genre: @genre).has_partial_metadata?
    assert_not Song.new(album: @album, genre: @genre).has_complete_metadata?
  end

  test "a song in review completes itself on save once it has a title and artist" do
    song = Song.create!(title: "Test Song", processing_status: "needs_review")
    assert_equal "needs_review", song.processing_status
    song.update!(artist: @artist)
    assert_equal "completed", song.reload.processing_status
  end

  test "only songs in review complete themselves" do
    song = Song.create!(title: "Test Song", artist: @artist, processing_status: "pending")
    assert_equal "pending", song.reload.processing_status
  end

  test "search scopes match case-insensitively on title, artist and genre" do
    assert_equal [ songs(:one) ], Song.search_by_title("test so").to_a
    assert_equal [ songs(:two) ], Song.search_by_artist("ANOTHER").to_a
    assert_equal [ songs(:one) ], Song.search_by_genre("rock").to_a
    assert_empty Song.search_by_title("no such song")
  end

  test "by_genre and by_genre_name pick a genre's songs" do
    assert_equal [ songs(:two) ], Song.by_genre(genres(:two)).to_a
    assert_equal [ songs(:one) ], Song.by_genre_name("Rock").to_a
  end

  test "an attached file has to be audio" do
    song = attach_audio(Song.new(title: "Test Song", user: @user))
    assert song.valid?

    song = attach_audio(Song.new(title: "Test Song", user: @user), filename: "test.txt", content_type: "text/plain")
    assert_not song.valid?
    assert_includes song.errors[:audio_file], "must be an audio file (mp3, m4a, mp4, ogg, flac, wav, aac)"
  end

  test "extract_metadata_from_file is nil without a file" do
    assert_nil Song.new(title: "Test Song").extract_metadata_from_file
  end

  test "extract_metadata_from_file hands the file to the processor and returns what it found" do
    song = attach_audio(Song.new(title: "Test Song", original_filename: "Artist - Title.mp3"))
    song.save!
    found = { title: "Extracted Title", artist: "Extracted Artist", duration: 180, file_format: "mp3", file_size: 1024 }
    seen = nil
    processor = Struct.new(:found) { def process = found }.new(found)
    builder = lambda do |path, content_type, byte_size, original_filename:|
      seen = { content: File.binread(path), content_type: content_type, byte_size: byte_size, original_filename: original_filename }
      processor
    end

    AudioFileProcessor.stub :new, builder do
      assert_equal found, song.extract_metadata_from_file
    end
    assert_equal({ content: AUDIO, content_type: "audio/mpeg", byte_size: AUDIO.bytesize, original_filename: "Artist - Title.mp3" }, seen)
  end

  test "extract_metadata_from_file finds only format and size in a file with no tags" do
    song = attach_audio(Song.new(title: "Test Song"))
    song.save!
    assert_equal({ file_format: "mp3", file_size: AUDIO.bytesize, title: nil, artist: nil, album: nil, genre: nil,
                   track_number: nil, duration: nil }, song.extract_metadata_from_file)
  end

  test "extract_metadata_from_file reports an error instead of raising" do
    song = attach_audio(Song.new(title: "Test Song"))
    song.save!
    AudioFileProcessor.stub :new, ->(*, **) { raise "Test error" } do
      assert_equal({ error: "Test error" }, song.extract_metadata_from_file)
    end
  end

  test "schedule_processing enqueues the processing job for the song" do
    song = Song.create!(title: "Test Song")
    assert_enqueued_with(job: AudioFileProcessingJob, args: [ song.id ]) do
      song.send(:schedule_processing)
    end
  end

  # The model enqueues processing itself only when inline processing is off
  # (config/initializers/processing.rb); with it on, the upload controllers process the file directly.
  test "creating a song enqueues processing exactly when inline processing is off" do
    song = attach_audio(Song.new(title: "Test Song", user: @user))
    if Rails.configuration.x.inline_audio_processing
      assert_no_enqueued_jobs(only: AudioFileProcessingJob) { song.save! }
    else
      assert_enqueued_with(job: AudioFileProcessingJob) { song.save! }
    end
  end

  test "an update is worth reprocessing only with a file and an unfinished status" do
    song = Song.create!(title: "Test Song", processing_status: "needs_review")
    assert_not song.send(:should_reschedule_processing?), "no file"

    attach_audio(song)
    { nil => true, "pending" => true, "needs_review" => true, "processing" => false, "completed" => false }.each do |status, expected|
      song.processing_status = status
      assert_equal expected, song.send(:should_reschedule_processing?), "status #{status.inspect}"
    end

    song.assign_attributes(processing_status: "failed", processing_error: nil)
    assert song.send(:should_reschedule_processing?), "failed with no recorded error"
    song.processing_error = "ffprobe exploded"
    assert_not song.send(:should_reschedule_processing?), "failed with an error"
  end

  test "display_title is the title" do
    assert_equal "Test Song", Song.new(title: "Test Song").display_title
  end

  test "artist_display prefers the credit line over the artist's name" do
    song = Song.new(artist: @artist)
    assert_equal "Test Artist", song.artist_display
    song.artist_credit = "Test Artist feat. Another Artist"
    assert_equal "Test Artist feat. Another Artist", song.artist_display
    assert_nil Song.new.artist_display
  end

  test "belongs to an optional user, artist, album and genre" do
    song = songs(:one)
    assert_equal users(:admin), song.user
    assert_equal artists(:one), song.artist
    assert_equal albums(:one), song.album
    assert_equal genres(:one), song.genre
    assert_not song.audio_file.attached?
  end
end
