require "test_helper"

class BulkOperationsControllerTest < ActionDispatch::IntegrationTest
  def csv_upload(text, name: "songs.csv", type: "text/csv")
    file = Tempfile.new([ "songs", ".csv" ])
    file.write(text)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, original_filename: name)
  end

  test "a regular user is turned away" do
    sign_in users(:user)
    get bulk_operations_path
    assert_redirected_to root_path
    post bulk_delete_bulk_operations_path, params: { song_ids: songs(:one).id }
    assert_redirected_to root_path
    assert Song.exists?(songs(:one).id)
  end

  test "a moderator sees the page" do
    sign_in users(:moderator)
    get bulk_operations_path
    assert_response :success
    assert_select "form[action=?]", upload_csv_bulk_operations_path
  end

  test "CSV import creates songs with their artist, album and genre" do
    sign_in users(:moderator)
    csv = <<~CSV
      title,track_number,duration,file_format,file_size,artist_name,album_title,album_release_date,genre_name
      Imported One,1,180,mp3,5242880,New CSV Artist,New CSV Album,2023-01-01,CSV Genre
      Imported Two,,,,,New CSV Artist,,,
      ,3,,,,Nobody,,,
      Bad Format,1,10,exe,,,,,
    CSV
    assert_difference -> { Song.count } => 2, -> { Artist.where(name: "New CSV Artist").count } => 1 do
      post upload_csv_bulk_operations_path, params: { file: csv_upload(csv) }
    end
    assert_redirected_to bulk_operations_path
    assert_equal "Imported 2 songs.", flash[:notice]
    assert_match "2 rows were skipped", flash[:alert]
    assert_match "row 4", flash[:alert]
    assert_not Artist.exists?(name: "Nobody")

    song = Song.find_by!(title: "Imported One")
    assert_equal "New CSV Artist", song.artist.name
    assert_equal "New CSV Album", song.album.title
    assert_equal Date.new(2023, 1, 1), song.album.release_date
    assert_equal "CSV Genre", song.genre.name
    assert_equal 180, song.duration
    assert_equal users(:moderator), song.user
    assert_equal song.artist, Song.find_by!(title: "Imported Two").artist
  end

  test "a CSV sent with a spreadsheet content type is accepted by its file name" do
    sign_in users(:moderator)
    assert_difference -> { Song.count }, 1 do
      post upload_csv_bulk_operations_path, params: { file: csv_upload("title\nFrom Excel\n", type: "application/vnd.ms-excel") }
    end
  end

  test "a file that is not a CSV is refused" do
    sign_in users(:moderator)
    assert_no_difference -> { Song.count } do
      post upload_csv_bulk_operations_path, params: { file: csv_upload("title\nNope\n", name: "songs.txt", type: "text/plain") }
    end
    assert_equal "Please upload a CSV file", flash[:alert]
  end

  test "export lists every song" do
    sign_in users(:moderator)
    get export_csv_bulk_operations_path
    assert_response :success
    assert_equal "text/csv", response.media_type
    rows = CSV.parse(response.body, headers: true)
    assert_equal Song.count, rows.size
    assert_includes rows.map { |r| r["id"] }, songs(:one).id
  end

  test "bulk delete removes the listed songs and reports what it could not use" do
    sign_in users(:moderator)
    missing = SecureRandom.uuid
    ids = "#{songs(:one).id},\n #{songs(:two).id.upcase} #{missing}, 17"
    assert_difference -> { Song.count }, -2 do
      post bulk_delete_bulk_operations_path, params: { song_ids: ids }
    end
    assert_redirected_to bulk_operations_path
    assert_match "Deleted 2 songs", flash[:alert]
    assert_match "Song #{missing} not found", flash[:alert]
    assert_match "17 is not a song ID", flash[:alert]
  end

  test "bulk delete with nothing entered deletes nothing" do
    sign_in users(:moderator)
    assert_no_difference -> { Song.count } do
      post bulk_delete_bulk_operations_path, params: { song_ids: " , " }
    end
    assert_equal "Please enter the IDs of the songs to delete", flash[:alert]
  end
end
