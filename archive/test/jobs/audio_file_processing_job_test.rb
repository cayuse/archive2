require "test_helper"

class AudioFileProcessingJobTest < ActiveJob::TestCase
  def setup
    @user = users(:admin)
    @artist = artists(:one)
    @album = albums(:one)
    @genre = genres(:one)
  end

  test "should process song with audio file" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    # Attach a test audio file
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction
    mock_metadata = {
      title: "Extracted Title",
      artist: "Extracted Artist",
      album: "Extracted Album",
      genre: "Rock",
      track_number: 1,
      duration: 180,
      file_format: "mp3",
      file_size: 1024
    }
    
    song.stub :extract_metadata_from_file, mock_metadata do
      assert_changes -> { song.reload.processing_status }, from: 'pending', to: 'completed' do
        AudioFileProcessingJob.perform_now(song.id)
      end
      
      song.reload
      assert_equal "Extracted Title", song.title
      assert_equal "Extracted Artist", song.artist.name
      assert_equal "Extracted Album", song.album.title
      assert_equal "Rock", song.genre.name
      assert_equal 1, song.track_number
      assert_equal 180, song.duration
      assert_equal "mp3", song.file_format
      assert_equal 1024, song.file_size
    end
  end

  test "should handle processing error" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction to raise an error
    song.stub :extract_metadata_from_file, { error: "Test error" } do
      assert_changes -> { song.reload.processing_status }, from: 'pending', to: 'failed' do
        AudioFileProcessingJob.perform_now(song.id)
      end
      
      song.reload
      assert_equal "Test error", song.processing_error
    end
  end

  test "should handle no metadata found" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction to return no metadata
    song.stub :extract_metadata_from_file, { error: "No metadata found in filename" } do
      assert_changes -> { song.reload.processing_status }, from: 'pending', to: 'needs_review' do
        AudioFileProcessingJob.perform_now(song.id)
      end
      
      song.reload
      assert_nil song.processing_error
    end
  end

  test "should skip if no audio file attached" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    # No audio file attached
    assert_no_changes -> { song.reload.processing_status } do
      AudioFileProcessingJob.perform_now(song.id)
    end
  end

  test "should skip if already processing" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'processing'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Should not change status if already processing
    assert_no_changes -> { song.reload.processing_status } do
      AudioFileProcessingJob.perform_now(song.id)
    end
  end

  test "should skip if already completed" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'completed'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Should not change status if already completed
    assert_no_changes -> { song.reload.processing_status } do
      AudioFileProcessingJob.perform_now(song.id)
    end
  end

  test "should create default artist and album if none provided" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction with no artist/album
    mock_metadata = {
      title: "Extracted Title",
      file_format: "mp3",
      file_size: 1024
    }
    
    song.stub :extract_metadata_from_file, mock_metadata do
      assert_difference "Artist.count", 1 do
        assert_difference "Album.count", 1 do
          AudioFileProcessingJob.perform_now(song.id)
        end
      end
      
      song.reload
      assert_equal "Unknown Artist", song.artist.name
      assert_equal "Unknown Album", song.album.title
      assert_equal "needs_review", song.processing_status
    end
  end

  test "should create default genre if none provided" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction with no genre
    mock_metadata = {
      title: "Extracted Title",
      artist: "Extracted Artist",
      album: "Extracted Album",
      file_format: "mp3",
      file_size: 1024
    }
    
    song.stub :extract_metadata_from_file, mock_metadata do
      assert_difference "Genre.count", 1 do
        AudioFileProcessingJob.perform_now(song.id)
      end
      
      song.reload
      assert_equal "Unknown Genre", song.genre.name
      assert_equal "needs_review", song.processing_status
    end
  end

  test "should set completed status with complete metadata" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction with complete metadata
    mock_metadata = {
      title: "Extracted Title",
      artist: "Extracted Artist",
      album: "Extracted Album",
      genre: "Rock",
      file_format: "mp3",
      file_size: 1024
    }
    
    song.stub :extract_metadata_from_file, mock_metadata do
      assert_changes -> { song.reload.processing_status }, from: 'pending', to: 'completed' do
        AudioFileProcessingJob.perform_now(song.id)
      end
    end
  end

  test "should set needs_review status with partial metadata" do
    song = Song.create!(
      title: "Test Song",
      user: @user,
      processing_status: 'pending'
    )
    
    song.audio_file.attach(
      io: StringIO.new("fake audio content"),
      filename: "test.mp3",
      content_type: "audio/mpeg"
    )
    
    # Mock the metadata extraction with partial metadata
    mock_metadata = {
      title: "Extracted Title",
      artist: "Extracted Artist",
      file_format: "mp3",
      file_size: 1024
    }
    
    song.stub :extract_metadata_from_file, mock_metadata do
      assert_changes -> { song.reload.processing_status }, from: 'pending', to: 'needs_review' do
        AudioFileProcessingJob.perform_now(song.id)
      end
    end
  end

  test "should handle song not found" do
    # Try to process a non-existent song
    assert_nothing_raised do
      AudioFileProcessingJob.perform_now(99999)
    end
  end
end 