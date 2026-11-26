require "test_helper"

# The web UI's song search (GET /songs/search), which is what the search box calls.
class SongsControllerTest < ActionDispatch::IntegrationTest
  def found_ids
    JSON.parse(response.body)["songs"].map { |s| s["id"] }
  end

  test "search needs a login" do
    get search_songs_path, params: { q: "Test" }
    assert_redirected_to login_path
  end

  test "search renders the matching songs for a logged-in user" do
    sign_in users(:user)
    get search_songs_path, params: { q: "Another" }
    assert_response :success
    assert_includes response.body, songs(:two).title
    assert_not_includes response.body, songs(:one).title
  end

  test "an empty search returns every song" do
    sign_in users(:user)
    get search_songs_path, params: { q: "" }, as: :json
    assert_response :success
    assert_equal Song.pluck(:id).sort, found_ids.sort
  end

  test "search matches title, artist, album and genre" do
    sign_in users(:user)
    { "Test Song" => :one, "another artist" => :two, "Test Album" => :one, "jazz" => :two }.each do |query, song|
      get search_songs_path, params: { q: query }, as: :json
      assert_equal [ songs(song).id ], found_ids, "searching for #{query.inspect}"
    end
  end

  test "every search term has to match" do
    sign_in users(:user)
    get search_songs_path, params: { q: "song rock" }, as: :json
    assert_equal [ songs(:one).id ], found_ids
    get search_songs_path, params: { q: "test jazz" }, as: :json
    assert_empty found_ids
  end

  test "search treats LIKE wildcards literally" do
    sign_in users(:user)
    get search_songs_path, params: { q: "%" }, as: :json
    assert_empty found_ids
  end
end
