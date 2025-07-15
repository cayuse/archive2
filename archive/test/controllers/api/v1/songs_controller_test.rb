require "test_helper"

class Api::V1::SongsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:admin)
    @artist = artists(:one)
    @album = albums(:one)
    @genre = genres(:one)
    @song = songs(:one)
    
    # Create API token for testing
    @api_token = create_api_token(@user)
  end

  test "should get index" do
    get api_v1_songs_url, headers: { "Authorization" => "Bearer #{@api_token}" }
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json["success"]
    assert_kind_of Array, json["songs"]
  end

  test "should get show" do
    get api_v1_song_url(@song), headers: { "Authorization" => "Bearer #{@api_token}" }
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal @song.id, json["song"]["id"]
  end

  test "should require authentication for index" do
    get api_v1_songs_url
    assert_response :unauthorized
    
    json = JSON.parse(response.body)
    assert_not json["success"]
    assert_equal "Missing API token", json["message"]
  end

  test "should require authentication for show" do
    get api_v1_song_url(@song)
    assert_response :unauthorized
  end

  test "should upload song with audio file" do
    audio_file = fixture_file_upload("files/test.mp3", "audio/mpeg")
    
    assert_difference "Song.count", 1 do
      post api_v1_songs_bulk_upload_url, 
           params: { audio_file: audio_file },
           headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :created
    
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal "Song uploaded successfully", json["message"]
    assert json["song"]["id"]
    assert_equal "processing", json["song"]["processing_status"]
  end

  test "should upload song with metadata" do
    audio_file = fixture_file_upload("files/test.mp3", "audio/mpeg")
    
    assert_difference "Song.count", 1 do
      post api_v1_songs_bulk_upload_url, 
           params: { 
             audio_file: audio_file,
             title: "Test Song",
             artist_name: "Test Artist",
             album_title: "Test Album",
             genre_name: "Rock"
           },
           headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :created
    
    json = JSON.parse(response.body)
    assert json["success"]
    
    # Check that metadata was applied
    song = Song.last
    assert_equal "Test Song", song.title
    assert_equal "Test Artist", song.artist.name
    assert_equal "Test Album", song.album.title
    assert_equal "Rock", song.genre.name
    assert_equal "completed", song.processing_status
  end

  test "should upload song with skip metadata extraction" do
    audio_file = fixture_file_upload("files/test.mp3", "audio/mpeg")
    
    assert_difference "Song.count", 1 do
      post api_v1_songs_bulk_upload_url, 
           params: { 
             audio_file: audio_file,
             title: "Test Song",
             skip_metadata_extraction: "true"
           },
           headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :created
    
    json = JSON.parse(response.body)
    assert json["success"]
    
    # Check that no background job was scheduled
    song = Song.last
    assert_equal "new", song.processing_status
  end

  test "should reject invalid audio file" do
    text_file = fixture_file_upload("files/test.txt", "text/plain")
    
    assert_no_difference "Song.count" do
      post api_v1_songs_bulk_upload_url, 
           params: { audio_file: text_file },
           headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :bad_request
    
    json = JSON.parse(response.body)
    assert_not json["success"]
    assert_equal "Invalid audio file format", json["message"]
  end

  test "should require audio file for upload" do
    assert_no_difference "Song.count" do
      post api_v1_songs_bulk_upload_url, 
           params: {},
           headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :bad_request
    
    json = JSON.parse(response.body)
    assert_not json["success"]
    assert_equal "No audio file provided", json["message"]
  end

  test "should require upload permissions" do
    # Create a regular user (not admin/moderator)
    regular_user = User.create!(
      email: "user@example.com",
      password: "password123",
      role: 0
    )
    regular_token = create_api_token(regular_user)
    
    audio_file = fixture_file_upload("files/test.mp3", "audio/mpeg")
    
    assert_no_difference "Song.count" do
      post api_v1_songs_bulk_upload_url, 
           params: { audio_file: audio_file },
           headers: { "Authorization" => "Bearer #{regular_token}" }
    end
    
    assert_response :forbidden
    
    json = JSON.parse(response.body)
    assert_not json["success"]
    assert_equal "Insufficient permissions for upload", json["message"]
  end

  test "should handle bulk create" do
    songs_data = [
      {
        title: "Song 1",
        artist_id: @artist.id,
        album_id: @album.id,
        genre_id: @genre.id
      },
      {
        title: "Song 2",
        artist_id: @artist.id
      }
    ]
    
    assert_difference "Song.count", 2 do
      post api_v1_songs_bulk_create_url,
           params: { songs: songs_data },
           headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal 2, json["summary"]["successful"]
    assert_equal 0, json["summary"]["failed"]
  end

  test "should handle bulk update" do
    songs_data = [
      {
        id: @song.id,
        title: "Updated Title"
      }
    ]
    
    patch api_v1_songs_bulk_update_url,
           params: { songs: songs_data },
           headers: { "Authorization" => "Bearer #{@api_token}" }
    
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal 1, json["summary"]["successful"]
    
    @song.reload
    assert_equal "Updated Title", @song.title
  end

  test "should handle bulk destroy" do
    song_ids = [@song.id]
    
    assert_difference "Song.count", -1 do
      delete api_v1_songs_bulk_destroy_url,
             params: { song_ids: song_ids },
             headers: { "Authorization" => "Bearer #{@api_token}" }
    end
    
    assert_response :success
    
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal 1, json["deleted_count"]
  end

  test "should export songs to CSV" do
    get api_v1_songs_export_url, headers: { "Authorization" => "Bearer #{@api_token}" }
    
    assert_response :success
    assert_equal "text/csv", response.content_type
    assert_includes response.headers["Content-Disposition"], "attachment"
  end

  test "should handle expired token" do
    expired_token = create_expired_api_token(@user)
    
    get api_v1_songs_url, headers: { "Authorization" => "Bearer #{expired_token}" }
    assert_response :unauthorized
    
    json = JSON.parse(response.body)
    assert_not json["success"]
    assert_equal "API token expired", json["message"]
  end

  test "should handle invalid token" do
    get api_v1_songs_url, headers: { "Authorization" => "Bearer invalid_token" }
    assert_response :unauthorized
    
    json = JSON.parse(response.body)
    assert_not json["success"]
    assert_equal "Invalid API token", json["message"]
  end

  private

  def create_api_token(user)
    payload = {
      user_id: user.id,
      exp: Time.current.to_i + 3600 # 1 hour from now
    }
    Base64.urlsafe_encode64(payload.to_json)
  end

  def create_expired_api_token(user)
    payload = {
      user_id: user.id,
      exp: Time.current.to_i - 3600 # 1 hour ago
    }
    Base64.urlsafe_encode64(payload.to_json)
  end
end 