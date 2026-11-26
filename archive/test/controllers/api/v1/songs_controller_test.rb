require "test_helper"

class Api::V1::SongsControllerTest < ActionDispatch::IntegrationTest
  AUDIO = "not really audio, but bytes enough to range over".freeze

  setup do
    @admin = users(:admin)
    @song = songs(:one)
  end

  def json = JSON.parse(response.body)

  def attach_audio(song, content = AUDIO)
    song.audio_file.attach(io: StringIO.new(content), filename: "test.mp3", content_type: "audio/mpeg")
    song.update!(file_format: "mp3")
    song
  end

  def upload(name: "test.mp3", type: "audio/mpeg")
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.binmode
    file.write(AUDIO)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, original_filename: name)
  end

  # --- authentication ---

  test "index needs a token" do
    get api_v1_songs_url
    assert_response :unauthorized
    assert_equal false, json["success"]
    assert_equal "Missing API token", json["message"]
  end

  test "a login session is not enough for index" do
    sign_in @admin
    get api_v1_songs_url
    assert_response :unauthorized
  end

  test "a garbage token is refused" do
    get api_v1_songs_url, headers: { "Authorization" => "Bearer invalid_token" }
    assert_response :unauthorized
    assert_equal "Invalid API token", json["message"]
  end

  test "an unencrypted token is refused" do
    forged = Base64.urlsafe_encode64({ user_id: @admin.id, exp: 1.hour.from_now.to_i }.to_json)
    get api_v1_songs_url, headers: { "Authorization" => "Bearer #{forged}" }
    assert_response :unauthorized
    assert_equal "Invalid API token", json["message"]
  end

  test "an expired token is refused" do
    get api_v1_songs_url, headers: api_headers(@admin, expires_in: -1.minute)
    assert_response :unauthorized
    assert_equal "API token expired", json["message"]
  end

  test "a token for a deleted user is refused" do
    gone = User.create!(name: "Gone Soon", email: "gone@example.com", password: "password123")
    headers = api_headers(gone)
    gone.destroy
    get api_v1_songs_url, headers: headers
    assert_response :unauthorized
    assert_equal "Invalid API token", json["message"]
  end

  # --- index ---

  test "index lists songs with their names and pagination" do
    get api_v1_songs_url, headers: api_headers(users(:user))
    assert_response :success
    assert json["success"]
    assert_equal Song.pluck(:id).sort, json["songs"].map { |s| s["id"] }.sort
    listed = json["songs"].find { |s| s["id"] == @song.id }
    assert_equal "Test Song", listed["title"]
    assert_equal "Test Artist", listed["artist"]
    assert_equal "Test Album", listed["album"]
    assert_equal "Rock", listed["genre"]
    assert_equal "completed", listed["processing_status"]
    assert_equal({ "current_page" => 1, "total_pages" => 1, "total_count" => Song.count, "limit" => 50 }, json["pagination"])
  end

  test "index pages by limit" do
    get api_v1_songs_url, params: { limit: 1, page: 2, sort_by: "title", sort_order: "asc" }, headers: api_headers(@admin)
    assert_response :success
    assert_equal [ "Test Song" ], json["songs"].map { |s| s["title"] }
    assert_equal 2, json["pagination"]["current_page"]
    assert_equal 2, json["pagination"]["total_pages"]
    assert_equal 1, json["pagination"]["limit"]
  end

  test "index clamps the limit to 1..100" do
    get api_v1_songs_url, params: { limit: 5000 }, headers: api_headers(@admin)
    assert_equal 100, json["pagination"]["limit"]
    get api_v1_songs_url, params: { limit: 0 }, headers: api_headers(@admin)
    assert_equal 1, json["pagination"]["limit"]
  end

  test "index sorts by an allowed column in the asked order" do
    get api_v1_songs_url, params: { sort_by: "title", sort_order: "asc" }, headers: api_headers(@admin)
    assert_equal [ "Another Song", "Test Song" ], json["songs"].map { |s| s["title"] }
    get api_v1_songs_url, params: { sort_by: "title", sort_order: "desc" }, headers: api_headers(@admin)
    assert_equal [ "Test Song", "Another Song" ], json["songs"].map { |s| s["title"] }
  end

  test "index ignores a sort column that is not allowed" do
    get api_v1_songs_url, params: { sort_by: "title; DROP TABLE songs" }, headers: api_headers(@admin)
    assert_response :success
    assert_equal Song.count, json["songs"].size
  end

  test "index search needs every term to match somewhere" do
    get api_v1_songs_url, params: { search: "song rock" }, headers: api_headers(@admin)
    assert_response :success
    assert_equal [ @song.id ], json["songs"].map { |s| s["id"] }
    get api_v1_songs_url, params: { search: "test jazz" }, headers: api_headers(@admin)
    assert_response :success
    assert_empty json["songs"]
  end

  test "index search can be combined with a sort" do
    get api_v1_songs_url, params: { search: "song", sort_by: "title", sort_order: "asc" }, headers: api_headers(@admin)
    assert_response :success
    assert_equal [ "Another Song", "Test Song" ], json["songs"].map { |s| s["title"] }
    get api_v1_songs_url, params: { search: "song", sort_by: "created_at" }, headers: api_headers(@admin)
    assert_response :success
  end

  # --- show / download / stream ---

  test "show needs a token or a login" do
    get api_v1_song_url(@song)
    assert_response :unauthorized
    get stream_api_v1_song_url(@song)
    assert_response :unauthorized
    get download_api_v1_song_url(@song)
    assert_response :unauthorized
  end

  test "show describes the song and where to fetch it" do
    attach_audio(@song)
    get api_v1_song_url(@song), headers: api_headers(users(:user))
    assert_response :success
    assert json["success"]
    song = json["song"]
    assert_equal @song.id, song["id"]
    assert_equal "Test Song", song["title"]
    assert_equal "Test Artist", song["artist"]
    assert_equal "Test Album", song["album"]
    assert_equal "Rock", song["genre"]
    assert_equal "mp3", song["file_format"]
    assert_equal AUDIO.bytesize, song["file_size"]
    assert_equal download_api_v1_song_url(@song), song["download_url"]
    assert_equal stream_api_v1_song_url(@song), song["stream_url"]
  end

  test "show accepts a browser login in place of a token" do
    attach_audio(@song)
    sign_in users(:user)
    get api_v1_song_url(@song)
    assert_response :success
    assert_equal @song.id, json["song"]["id"]
  end

  test "show with include=binary sends the file itself" do
    attach_audio(@song)
    get api_v1_song_url(@song), params: { include: "binary" }, headers: api_headers(@admin)
    assert_response :success
    assert_equal AUDIO, response.body
    assert_equal "audio/mpeg", response.media_type
  end

  test "download sends the file as an attachment named for artist and title" do
    attach_audio(@song)
    get download_api_v1_song_url(@song), headers: api_headers(@admin)
    assert_response :success
    assert_equal AUDIO, response.body
    assert_equal "audio/mpeg", response.media_type
    assert_match(/\Aattachment; filename="Test Artist - Test Song\.mp3"/, response.headers["Content-Disposition"])
  end

  test "stream sends the whole file inline" do
    attach_audio(@song)
    get stream_api_v1_song_url(@song), headers: api_headers(@admin)
    assert_response :success
    assert_equal AUDIO, response.body
    assert_equal "bytes", response.headers["Accept-Ranges"]
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
  end

  test "stream honours a byte range" do
    attach_audio(@song)
    get stream_api_v1_song_url(@song), headers: api_headers(@admin).merge("Range" => "bytes=4-9")
    assert_response :partial_content
    assert_equal AUDIO.byteslice(4, 6), response.body
    assert_equal "bytes 4-9/#{AUDIO.bytesize}", response.headers["Content-Range"]
  end

  test "stream serves an open-ended range to the end of the file" do
    attach_audio(@song)
    get stream_api_v1_song_url(@song), headers: api_headers(@admin).merge("Range" => "bytes=10-")
    assert_response :partial_content
    assert_equal AUDIO.byteslice(10..), response.body
    assert_equal "bytes 10-#{AUDIO.bytesize - 1}/#{AUDIO.bytesize}", response.headers["Content-Range"]
  end

  test "stream works for the browser player's login session" do
    attach_audio(@song)
    sign_in users(:user)
    get stream_api_v1_song_url(@song)
    assert_response :success
    assert_equal AUDIO, response.body
  end

  test "show describes a song that has no file yet, with no size" do
    get api_v1_song_url(@song), headers: api_headers(@admin)
    assert_response :success
    assert_equal @song.id, json["song"]["id"]
    assert_nil json["song"]["file_size"]
  end

  # --- radio / rate ---

  test "radio needs a token" do
    get radio_api_v1_song_url(@song)
    assert_response :unauthorized
  end

  test "radio returns the seed, the steer it was given and a list of songs" do
    get radio_api_v1_song_url(@song), params: { energy: "0.5", count: 5 }, headers: api_headers(users(:user))
    assert_response :success
    assert json["success"]
    assert_equal @song.id, json["seed"]["id"]
    assert_equal "Test Artist", json["seed"]["artist"]
    assert_equal false, json["analyzed"]
    assert_equal({ "energy" => "0.5" }, json["steer"])
    assert_kind_of Array, json["songs"]
    assert_not_includes json["songs"].map { |s| s["id"] }, @song.id
  end

  test "rate records a thumb for the caller and can clear it" do
    user = users(:user)
    post rate_api_v1_song_url(@song), params: { value: 1 }, headers: api_headers(user)
    assert_response :success
    assert_equal({ "success" => true, "song_id" => @song.id, "value" => 1 }, json)
    assert_equal "up", StationFeedback.standing(user: user, song: @song)

    post rate_api_v1_song_url(@song), params: { value: -1 }, headers: api_headers(user)
    assert_equal(-1, json["value"])
    assert_equal "down", StationFeedback.standing(user: user, song: @song)

    post rate_api_v1_song_url(@song), params: { value: 0 }, headers: api_headers(user)
    assert_equal 0, json["value"]
    assert_nil StationFeedback.standing(user: user, song: @song)
  end

  test "rate needs a token" do
    assert_no_difference "StationFeedback.count" do
      post rate_api_v1_song_url(@song), params: { value: 1 }
    end
    assert_response :unauthorized
  end

  # --- bulk_upload ---

  test "upload needs a token" do
    assert_no_difference "Song.count" do
      post bulk_upload_api_v1_songs_url, params: { audio_file: upload }
    end
    assert_response :unauthorized
  end

  test "a regular user may not upload" do
    assert_no_difference "Song.count" do
      post bulk_upload_api_v1_songs_url, params: { audio_file: upload }, headers: api_headers(users(:user))
    end
    assert_response :forbidden
    assert_equal false, json["success"]
    assert_equal "Insufficient permissions. Moderator or admin role required.", json["message"]
  end

  test "upload without a file is rejected" do
    assert_no_difference "Song.count" do
      post bulk_upload_api_v1_songs_url, headers: api_headers(@admin)
    end
    assert_response :unprocessable_entity
    assert_equal false, json["success"]
    assert_equal "No audio file provided", json["message"]
  end

  test "upload of something that is not audio is rejected" do
    assert_no_difference "Song.count" do
      post bulk_upload_api_v1_songs_url, params: { audio_file: upload(name: "notes.txt", type: "text/plain") },
                                         headers: api_headers(@admin)
    end
    assert_response :unprocessable_entity
    assert_equal "Failed to save song", json["message"]
    assert_includes json["errors"], "Audio file must be an audio file (mp3, m4a, mp4, ogg, flac, wav, aac)"
  end

  test "a moderator uploads a file with a title but no artist and it waits for review" do
    assert_difference "Song.count", 1 do
      post bulk_upload_api_v1_songs_url, params: { audio_file: upload(name: "mystery.mp3"), title: "Mystery" },
                                         headers: api_headers(users(:moderator))
    end
    assert_response :created
    assert json["success"]
    assert_equal "Song uploaded successfully", json["message"]
    song = Song.find(json["song"]["id"])
    assert song.audio_file.attached?
    assert_equal AUDIO, song.audio_file.download
    assert_equal "mystery.mp3", song.original_filename
    assert_equal "needs_review", song.processing_status
    assert_equal "needs_review", json["song"]["processing_status"]
    assert_equal "Mystery", song.title
    assert_nil song.artist
    assert_equal "mp3", song.file_format
    assert_equal AUDIO.bytesize, song.file_size
  end

  test "upload with a title and artist is complete, creating what it names" do
    assert_difference [ "Song.count", "Artist.count", "Album.count", "Genre.count" ], 1 do
      post bulk_upload_api_v1_songs_url, headers: api_headers(@admin), params: {
        audio_file: upload, title: "Uploaded Title", artist_name: "Uploaded Artist",
        album_title: "Uploaded Album", genre_name: "Uploaded Genre", track_number: 3, duration: 180
      }
    end
    assert_response :created
    assert_equal "Uploaded Title", json["song"]["title"]
    assert_equal "Uploaded Artist", json["song"]["artist"]
    assert_equal "Uploaded Album", json["song"]["album"]
    assert_equal "Uploaded Genre", json["song"]["genre"]
    assert_equal "completed", json["song"]["processing_status"]
    song = Song.find(json["song"]["id"])
    assert_equal 3, song.track_number
    assert_equal 180, song.duration
  end

  test "upload reuses an artist, album and genre that already exist" do
    assert_no_difference [ "Artist.count", "Album.count", "Genre.count" ] do
      post bulk_upload_api_v1_songs_url, headers: api_headers(@admin), params: {
        audio_file: upload, title: "Uploaded Title", artist_name: "Test Artist", album_title: "Test Album", genre_name: "Rock"
      }
    end
    assert_response :created
    song = Song.find(json["song"]["id"])
    assert_equal artists(:one), song.artist
    assert_equal albums(:one), song.album
    assert_equal genres(:one), song.genre
  end

  test "upload can skip reading the file and take the given filename" do
    post bulk_upload_api_v1_songs_url, headers: api_headers(@admin), params: {
      audio_file: upload, title: "Skipped", filename: "From Client.mp3", skip_post_processing: "true"
    }
    assert_response :created
    song = Song.find(json["song"]["id"])
    assert_equal "From Client.mp3", song.original_filename
    assert_equal "needs_review", song.processing_status
    assert_nil song.file_format
    assert_nil song.file_size
  end

  test "an upload with no title is named after its file until the tags are read" do
    assert_difference -> { Song.count }, 1 do
      post bulk_upload_api_v1_songs_url, params: { audio_file: upload(name: "Night Drive.mp3") }, headers: api_headers(@admin)
    end
    assert_response :success
    assert_equal "Night Drive", Song.order(:created_at).last.title
  end

  test "stream and download of a song with no audio file are a 404, not an error" do
    song = Song.create!(title: "No File", user: @admin)
    get stream_api_v1_song_url(song), headers: api_headers(@admin)
    assert_response :not_found
    get download_api_v1_song_url(song), headers: api_headers(@admin)
    assert_response :not_found
  end
end
