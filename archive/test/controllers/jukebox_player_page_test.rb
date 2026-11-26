require "test_helper"

class JukeboxPlayerPageTest < ActionDispatch::IntegrationTest
  test "the player page is never cached and pins its scripts to the build it reports" do
    owner = users(:moderator)
    jukebox = Jukebox.create!(owner: owner, name: "Page", guest_password: "pppp")
    sign_in owner
    get player_jukebox_path(jukebox)
    assert_response :success
    assert_match "no-store", response.headers["Cache-Control"]
    build = response.body[/window\.AJB_BUILD = "([0-9a-f]{10})"/, 1]
    assert build, "the page names its build"
    assert_includes response.body, "/javascripts/ajb/models/AudioEngine.js?v=#{build}"
    assert_no_match(/howler/i, response.body[/<script[^>]*howler[^>]*>/i].to_s)

    get guest_jukebox_path(jukebox)
    assert_match "no-store", response.headers["Cache-Control"]
  end
end
