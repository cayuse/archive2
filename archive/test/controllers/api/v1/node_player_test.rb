require "test_helper"

# Server-side playback over the API: the daemon's poll, what it may touch, and the remote's transport.
class Api::V1::NodePlayerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:moderator)
    @other = users(:admin)
    @node = ArchiveNode.current
    @node.update!(local_playback: true)
    @node.regenerate_player_token
    @node.users << @owner
    @jukebox = Jukebox.create!(owner: @owner, name: "Party", guest_password: "pppp", admin_password: "adminpw")
    @daemon = { "X-Node-Token" => @node.player_token }
  end

  def bearer(user)
    payload = { user_id: user.id, exp: 1.hour.from_now.to_i }
    encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
    { "Authorization" => "Bearer #{Base64.urlsafe_encode64(encryptor.encrypt_and_sign(payload.to_json))}" }
  end

  def json = JSON.parse(response.body)

  test "sync needs the node token or a granted person" do
    post "/api/v1/node_player/sync", as: :json
    assert_response :unauthorized
    post "/api/v1/node_player/sync", headers: { "X-Node-Token" => "nope" }, as: :json
    assert_response :unauthorized
    post "/api/v1/node_player/sync", headers: bearer(@other), as: :json
    assert_response :forbidden
    post "/api/v1/node_player/sync", headers: @daemon, params: { ack: 0, state: { volume: 33 } }, as: :json
    assert_response :success
    assert_nil json["jukebox"]
    assert_equal 33, @node.reload.player_state["volume"]
  end

  test "the owner puts a jukebox on the speakers and the daemon is told, with the song to resume" do
    @jukebox.update!(current_song: songs(:one), current_position: 20, is_playing: true, last_status_update: 1.second.ago)
    post "/api/v1/jukeboxes/#{@jukebox.id}/server_playback", headers: bearer(@owner), params: { on: true }, as: :json
    assert_response :success
    post "/api/v1/node_player/sync", headers: @daemon, params: { ack: 0 }, as: :json
    j = json["jukebox"]
    assert_equal @jukebox.id, j["id"]
    assert_equal "play", j["transport"]
    assert_equal songs(:one).id, j["resume"]["song"]["id"]
    assert_match %r{/s/}, j["resume"]["song"]["play_url"]
    assert_operator j["resume"]["position"], :>=, 20
  end

  test "someone without a grant cannot take the speakers" do
    mine = Jukebox.create!(owner: @other, name: "Mine", guest_password: "mmmm")
    post "/api/v1/jukeboxes/#{mine.id}/server_playback", headers: bearer(@other), params: { on: true }, as: :json
    assert_response :forbidden
    assert_not mine.reload.server_playback?
  end

  test "the daemon may drive the on-air jukebox and nothing else" do
    get "/api/v1/jukeboxes/#{@jukebox.id}/queue", headers: @daemon
    assert_response :forbidden
    @jukebox.start_server_playback!(transport: "play")
    get "/api/v1/jukeboxes/#{@jukebox.id}/queue", headers: @daemon
    assert_response :success
    post "/api/v1/jukeboxes/#{@jukebox.id}/playback_status", headers: @daemon,
         params: { current_song_id: songs(:one).id, position: 12.5, is_playing: true }, as: :json
    assert_response :success
    assert_equal 12.5, @jukebox.reload.current_position
    assert @jukebox.live?
    get "/api/v1/jukeboxes", headers: @daemon
    assert_response :forbidden
  end

  test "a browser player's reports are ignored once the daemon has the jukebox" do
    @jukebox.start_server_playback!(transport: "play")
    post "/api/v1/jukeboxes/#{@jukebox.id}/playback_status", headers: bearer(@owner),
         params: { current_song_id: songs(:one).id, position: 99, is_playing: true }, as: :json
    assert_response :success
    assert_equal true, json["server_playback"]
    assert_nil @jukebox.reload.current_song_id
  end

  test "transport from the remote, and from an admin-code guest" do
    post "/api/v1/jukeboxes/#{@jukebox.id}/transport", headers: bearer(@owner), params: { command: "play" }, as: :json
    assert_response :unprocessable_entity          # not on the speakers
    @jukebox.start_server_playback!
    post "/api/v1/jukeboxes/#{@jukebox.id}/transport", headers: bearer(@owner), params: { command: "play" }, as: :json
    assert_response :success
    assert_equal "play", @jukebox.reload.server_transport
    post "/api/v1/jukeboxes/#{@jukebox.id}/transport", headers: bearer(@other), params: { command: "stop" }, as: :json
    assert_response :forbidden
    post "/api/v1/jukeboxes/#{@jukebox.id}/transport", headers: bearer(@owner), params: { command: "skip" }, as: :json
    post "/api/v1/node_player/command", headers: bearer(@owner), params: { cmd: "volume", value: 250 }, as: :json
    assert_response :success
    post "/api/v1/node_player/sync", headers: @daemon, params: { ack: 0 }, as: :json
    assert_equal [ [ "skip", { "report" => true } ], [ "volume", 100 ] ], json["commands"].map { |c| c.values_at("cmd", "value") }
    get "/api/v1/jukeboxes/#{@jukebox.id}/status", headers: bearer(@owner)
    assert_equal true, json["jukebox"]["server"]["online"]
    assert_equal "play", json["jukebox"]["server"]["transport"]
  end
  test "a song that is playing or already handed to the player cannot be requested again" do
    playing, waiting = songs(:one), songs(:two)
    @jukebox.start_server_playback!
    @jukebox.update_columns(last_status_update: 1.hour.from_now)   # a player is reporting in, so guests may join
    @jukebox.ajb_played_songs.create!(song: playing, played_at: Time.current, source: "requested")

    post "/api/v1/guest/#{@jukebox.id}/request_song", params: { song_id: playing.id, password: "pppp" }
    assert_equal [ true, "playing" ], json.values_at("success", "outcome"), response.body
    post "/api/v1/jukeboxes/#{@jukebox.id}/queue", params: { song_id: playing.id }, headers: bearer(@owner)
    assert_response :conflict
    assert_equal 0, @jukebox.ajb_queue_items.count

    post "/api/v1/guest/#{@jukebox.id}/request_song", params: { song_id: waiting.id, password: "pppp" }
    assert_equal "added", json["outcome"]
    travel 20.minutes do   # long over: asking again is a new request
      post "/api/v1/guest/#{@jukebox.id}/request_song", params: { song_id: playing.id, password: "pppp" }
      assert_equal "added", json["outcome"]
    end
  end
end
