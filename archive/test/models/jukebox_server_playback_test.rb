require "test_helper"

class JukeboxServerPlaybackTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @node = ArchiveNode.current
    @a = Jukebox.create!(owner: @user, name: "A", guest_password: "aaaa")
    @b = Jukebox.create!(owner: @user, name: "B", guest_password: "bbbb")
  end

  test "an idle jukebox takes the speakers stopped" do
    @a.start_server_playback!
    assert @a.server_playback?
    assert_equal "stop", @a.server_transport
    assert_nil @a.server_resume
    assert_equal @a, Jukebox.on_air
  end

  test "a jukebox playing in a browser carries its song and place over" do
    @a.update!(current_song: songs(:one), current_position: 30, is_playing: true, last_status_update: 4.seconds.ago)
    @a.start_server_playback!
    assert_equal "play", @a.server_transport
    song, position = @a.server_resume
    assert_equal songs(:one), song
    assert_in_delta 34, position, 1.5
  end

  test "a paused browser jukebox comes over paused at the same place" do
    @a.update!(current_song: songs(:one), current_position: 30, is_playing: false, last_status_update: 4.seconds.ago)
    @a.start_server_playback!
    assert_equal "pause", @a.server_transport
    assert_in_delta 30, @a.server_resume.last, 0.01
  end

  test "only one jukebox has the speakers: turning B on takes them from A" do
    @a.update!(current_song: songs(:one), current_position: 10, is_playing: true, last_status_update: 2.seconds.ago)
    @a.start_server_playback!
    @b.start_server_playback!(transport: "play")
    @a.reload
    assert_not @a.server_playback?
    assert_not @a.is_playing
    assert_equal songs(:one), @a.current_song          # kept, so a browser player can pick it up
    assert_in_delta 12, @a.current_position, 1.5
    assert_equal @b, Jukebox.on_air
    assert_equal "play", @b.server_transport
  end

  test "transport: pause holds the place, stop forgets the song, skip goes to the daemon" do
    @a.update!(current_song: songs(:one), current_position: 10, is_playing: true, last_status_update: 3.seconds.ago)
    @a.start_server_playback!
    @a.transport!("pause")
    assert_equal "pause", @a.server_transport
    assert_not @a.is_playing
    assert_in_delta 13, @a.current_position, 1.5
    @a.transport!("skip", quiet: true)
    assert_equal [ [ "skip", { "report" => false } ] ], @node.reload.pending_player_commands.map { |c| c.values_at("cmd", "value") }
    @a.transport!("stop")
    assert_nil @a.current_song_id
    assert_nil @a.server_resume
    assert_raises(ArgumentError) { @a.transport!("explode") }
    assert_raises(ArgumentError) { @b.transport!("play") }   # not on the speakers
  end

  test "a song about to end is not resumed" do
    songs(:one).update_column(:duration, 200)
    @a.update!(current_song: songs(:one), current_position: 100, is_playing: false, server_playback: true, server_transport: "play")
    assert_in_delta 100, @a.server_resume.last, 0.01
    @a.update!(current_position: 198)
    assert_nil @a.server_resume
  end

  test "commands are acknowledged and expire" do
    @node.push_player_command!("volume", 40)
    @node.push_player_command!("skip")
    first, second = @node.player_checkin!(ack: 0, state: { "volume" => 50 })
    assert_equal %w[volume skip], [ first["cmd"], second["cmd"] ]
    assert @node.reload.player_online?
    assert_equal 50, @node.player_state["volume"]
    assert_equal [ "skip" ], @node.player_checkin!(ack: first["seq"], state: {}).map { |c| c["cmd"] }
    travel 1.minute do
      assert_not @node.reload.player_online?
      assert_empty @node.player_checkin!(ack: first["seq"], state: {})
    end
    assert_raises(ArgumentError) { @node.push_player_command!("rm -rf") }
  end

  test "a join code that is not a string is simply wrong" do
    assert_nil @a.guest_role_for([ "aaaa" ])
    assert_equal :guest, @a.guest_role_for("aaaa")
  end
end
