require "test_helper"

class JukeboxLinedUpTest < ActiveSupport::TestCase
  setup do
    @jukebox = Jukebox.create!(owner: users(:moderator), name: "Lined", guest_password: "pppp")
    @playing, @next = songs(:one), songs(:two)
  end

  def take(song, at)
    @jukebox.ajb_played_songs.create!(song: song, played_at: at, source: "random")
  end

  test "the song taken after the one playing is lined up until it starts" do
    take(@playing, 3.minutes.ago)
    @jukebox.update!(current_song_id: @playing.id)
    assert_nil @jukebox.lined_up_song

    take(@next, 10.seconds.ago)
    assert_equal @next, @jukebox.lined_up_song
    assert @jukebox.playing_or_lined_up?(@next)

    @jukebox.update!(current_song_id: @next.id)   # it started
    assert_nil @jukebox.lined_up_song
  end

  test "nothing is lined up when nothing is playing, or when the last taken song came before the current one" do
    take(@next, 2.minutes.ago)
    assert_nil @jukebox.lined_up_song
    take(@playing, 1.minute.ago)
    @jukebox.update!(current_song_id: @playing.id)
    assert_nil @jukebox.lined_up_song
  end
end
