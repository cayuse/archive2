require "test_helper"

class SongTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @artist = artists(:one)
    @album = albums(:one)
    @genre = genres(:one)
  end

  test "should create song with valid attributes" do
    song = Song.new(
      title: "Test Song",
      user: @user,
      artist: @artist,
      album: @album,
      genre: @genre
    )
    assert song.save
  end

  test "should require title" do
    song = Song.new(user: @user)
    assert_not song.save
    assert_includes song.errors[:title], "can't be blank"
  end

  test "should require user" do
    song = Song.new(title: "Test Song")
    assert_not song.save
    assert_includes song.errors[:user], "must exist"
  end

  test "should have processing status methods" do
    song = Song.new(title: "Test Song", user: @user)
    
    # Test default status
    assert song.processing_pending?
    assert_not song.processing_in_progress?
    assert_not song.processing_completed?
    assert_not song.processing_failed?
    assert_not song.needs_review?
    assert_not song.new_import?
  end

  test "should have metadata completeness methods" do
    song = Song.new(title: "Test Song", user: @user)
    
    # Test empty metadata
    assert_not song.has_complete_metadata?
    assert_not song.has_partial_metadata?
    assert song.has_no_metadata?
    
    # Test partial metadata
    song.artist = @artist
    assert_not song.has_complete_metadata?
    assert song.has_partial_metadata?
    assert_not song.has_no_metadata?
    
    # Test complete metadata
    song.album = @album
    song.genre = @genre
    assert song.has_complete_metadata?
    assert song.has_partial_metadata?
    assert_not song.has_no_metadata?
  end

  test "should have search scopes" do
    # Test search_by_title
    songs = Song.search_by_title("Test")
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test search_by_artist
    songs = Song.search_by_artist("Artist")
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test search_by_genre
    songs = Song.search_by_genre("Rock")
    assert_kind_of ActiveRecord::Relation, songs
  end

  test "should have processing status scopes" do
    # Test pending_processing scope
    songs = Song.pending_processing
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test processing scope
    songs = Song.processing
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test completed scope
    songs = Song.completed
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test failed scope
    songs = Song.failed
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test needs_review scope
    songs = Song.needs_review
    assert_kind_of ActiveRecord::Relation, songs
    
    # Test new_imports scope
    songs = Song.new_imports
    assert_kind_of ActiveRecord::Relation, songs
    

  end

  test "should validate audio file type" do
    song = Song.new(title: "Test Song", user: @user)
    
    # Test valid audio file
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    assert song.valid?
    
    # Test invalid file type
    song.audio_file.attach(
      io: StringIO.new("fake content"),
      filename: "test.txt",
      content_type: "text/plain"
    )
    assert_not song.valid?
    assert_includes song.errors[:audio_file], "must be an audio file"
  end

  test "should extract metadata from filename" do
    song = Song.new(title: "Test Song", user: @user)
    
    # Test with valid audio file
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "Artist - Album - 01 - Title.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the AudioFileProcessor to return test metadata
    mock_processor = Minitest::Mock.new
    mock_processor.expect :process, {
      title: "Extracted Title",
      artist: "Extracted Artist",
      album: "Extracted Album",
      genre: "Rock",
      track_number: 1,
      duration: 180,
      file_format: "mp3",
      file_size: 1024
    }
    
    AudioFileProcessor.stub :new, mock_processor do
      metadata = song.extract_metadata_from_file
      assert_equal "Extracted Title", metadata[:title]
      assert_equal "Extracted Artist", metadata[:artist]
      assert_equal "Extracted Album", metadata[:album]
      assert_equal "Rock", metadata[:genre]
      assert_equal 1, metadata[:track_number]
      assert_equal 180, metadata[:duration]
    end
  end

  test "should handle metadata extraction errors" do
    song = Song.new(title: "Test Song", user: @user)
    
    # Mock AudioFileProcessor to raise an error
    AudioFileProcessor.stub :new, ->(*args) { raise "Test error" } do
      metadata = song.extract_metadata_from_file
      assert_equal "Test error", metadata[:error]
    end
  end

  test "should schedule processing after create" do
    song = Song.new(title: "Test Song", user: @user)
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    assert_difference -> { AudioFileProcessingJob.jobs.size }, 1 do
      song.save!
    end
  end

  test "should not schedule processing without audio file" do
    song = Song.new(title: "Test Song", user: @user)
    
    assert_no_difference -> { AudioFileProcessingJob.jobs.size } do
      song.save!
    end
  end

  test "should display title correctly" do
    song = Song.new(title: "Test Song", user: @user)
    assert_equal "Test Song", song.display_title
  end

  test "should have associations" do
    song = Song.new(title: "Test Song", user: @user)
    
    # Test associations exist
    assert_respond_to song, :user
    assert_respond_to song, :artist
    assert_respond_to song, :album
    assert_respond_to song, :genre
    assert_respond_to song, :audio_file
  end
end 