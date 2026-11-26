require "test_helper"

class BulkOperationsControllerTest < ActionDispatch::IntegrationTest
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
    assert_select "form[action=?]", bulk_delete_bulk_operations_path
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
