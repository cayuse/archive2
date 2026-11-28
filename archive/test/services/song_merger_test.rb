require "test_helper"

class SongMergerTest < ActiveSupport::TestCase
  PRINT = Random.new(42).then { |r| Array.new(900) { r.rand(1 << 32) } }.freeze

  setup do
    @user = users(:moderator)
    @merger = SongMerger.new(source: "intake", log: Logger.new(IO::NULL))
  end

  def song(title, print: PRINT, duration: 200.0, **m)
    s = Song.create!(title: title, duration: duration.to_i)
    SongMeasurement.create!({ song: s, measure_version: 2, score_version: 1, verdict: "ok", lossless: false, kbps: 192,
                              eff_khz: 16.0, duration: duration, measured_at: Time.current, fingerprint_values: print }.merge(m))
    s
  end

  def flac(title, **m) = song(title, lossless: true, bits: 16, sample_rate: 44_100, kbps: 950, eff_khz: 21.0, **m)

  test "a song with no other copy is new and stays live" do
    a = song("Alone", print: Random.new(1).then { |r| Array.new(900) { r.rand(1 << 32) } })
    result = @merger.merge(a)
    assert_equal "new", result.outcome
    assert_not a.reload.hidden?
  end

  test "a better copy takes over: the old one is hidden, and playlists, queues and votes follow it" do
    old = song("Old mp3", verdict: "bad", problems: [ { "level" => "bad", "text" => "blowouts" } ])
    SongIssue.record_quality!(old, old.measurement, source: "audit")
    list = Playlist.create!(name: "Mine", user: @user)
    PlaylistsSong.create!(playlist: list, song: old, position: 3)
    jukebox = Jukebox.create!(owner: @user, name: "Kitchen", guest_password: "pppp")
    queued = AjbQueueItem.create!(jukebox: jukebox, song: old, source: "requested", position: 1)
    up = StationFeedback.create!(user: @user, song: old, kind: "up")
    slot = PlaylistsSong.find_by(playlist_id: list.id).position
    down = StationFeedback.create!(user: users(:admin), song: old, kind: "down")

    new_copy = flac("New flac")
    result = @merger.merge(new_copy)

    assert_equal "better", result.outcome
    assert_match(/lossless against lossy/, result.why)
    assert_equal new_copy.id, old.reload.canonical_song_id
    assert_equal [ new_copy.id ], PlaylistsSong.where(playlist_id: list.id).pluck(:song_id)
    assert_equal slot, PlaylistsSong.find_by(playlist_id: list.id).position, "the slot keeps its place"
    assert_equal new_copy.id, queued.reload.song_id
    assert_equal new_copy.id, up.reload.song_id
    assert_equal old.id, down.reload.song_id, "a thumbs-down on a broken copy was about the damage: it stays behind"
    assert_equal [ "superseded" ], old.issues.open.pluck(:kind)
    assert old.issues.find_by(kind: "broken").resolved_at, "broken is settled: what plays now is the new copy"
    assert_not_includes Song.live, old
    assert_equal new_copy, old.playable_song
  end

  test "a copy that is not better is kept, hidden onto the one already there" do
    there = flac("Already here")
    again = song("Arrived later")
    result = @merger.merge(again)
    assert_equal "not_better", result.outcome
    assert_equal there, result.canonical
    assert_equal there.id, again.reload.canonical_song_id
    assert_not there.reload.hidden?
    assert_equal [ "duplicate" ], again.issues.open.pluck(:kind)
  end

  test "an equal copy never takes over: re-releases do not flip-flop" do
    there = song("First", kbps: 256, eff_khz: 19.5)
    later = song("Second", kbps: 257, eff_khz: 20.0)
    assert_equal "not_better", @merger.merge(later).outcome
    assert_not there.reload.hidden?
  end

  test "both copies on one playlist: the survivor keeps the earlier slot and the playlist holds it once" do
    old = song("Old")
    list = Playlist.create!(name: "Both", user: @user)
    PlaylistsSong.create!(playlist: list, song: old, position: 2)
    new_copy = flac("New")
    PlaylistsSong.create!(playlist: list, song: new_copy, position: 7)
    before = PlaylistsSong.where(playlist_id: list.id).pluck(:song_id, :position).sort
    old_slot = before.to_h[old.id]
    assert_operator old_slot, :<, before.to_h[new_copy.id]
    merge = nil
    assert_difference -> { PlaylistsSong.where(playlist_id: list.id).count }, -1 do
      @merger.merge(new_copy)
      merge = SongMerge.find_by!(song: old)
    end
    assert_equal [ [ new_copy.id, old_slot ] ], PlaylistsSong.where(playlist_id: list.id).pluck(:song_id, :position)

    @merger.restore!(merge)
    assert_equal before, PlaylistsSong.where(playlist_id: list.id).pluck(:song_id, :position).sort
  end

  test "restore puts back every row the merge moved and makes the copy live again" do
    old = song("Old")
    list = Playlist.create!(name: "Mine", user: @user)
    PlaylistsSong.create!(playlist: list, song: old, position: 1)
    vote = StationFeedback.create!(user: @user, song: old, kind: "up")
    new_copy = flac("New")
    @merger.merge(new_copy)
    merge = SongMerge.find_by!(song: old)

    @merger.restore!(merge)
    assert_not old.reload.hidden?
    assert_equal [ old.id ], PlaylistsSong.where(playlist_id: list.id).pluck(:song_id)
    assert_equal old.id, vote.reload.song_id
    assert merge.reload.reverted_at
    assert_empty old.issues.open.where(kind: %w[superseded duplicate])
    assert_raises(ArgumentError) { @merger.restore!(merge) }
  end

  test "no chains: copies hidden onto a copy that is itself replaced point at the newest" do
    first = song("First", kbps: 128, eff_khz: 15.0)
    second = song("Second", kbps: 320, eff_khz: 19.5)
    assert_equal "better", @merger.merge(second).outcome
    assert_equal second.id, first.reload.canonical_song_id
    third = flac("Third")
    assert_equal "better", @merger.merge(third).outcome
    assert_equal [ third.id, third.id ], [ first.reload.canonical_song_id, second.reload.canonical_song_id ]
  end

  test "a different length is a different version (an edit), never merged" do
    album = song("Album version", duration: 240.0)
    edit = flac("Radio edit", duration: 190.0)
    assert_equal "new", @merger.merge(edit).outcome
    assert_not album.reload.hidden?
  end

  test "anything that adds a hidden copy to a queue or playlist adds the copy that plays" do
    old = song("Old")
    new_copy = flac("New")
    @merger.merge(new_copy)
    assert_equal [ new_copy.id ], Song.playable_ids([ old.id, new_copy.id, SecureRandom.uuid ])
    jukebox = Jukebox.create!(owner: @user, name: "Den", guest_password: "pppp")
    item = AjbQueueItem.create!(jukebox: jukebox, song_id: old.id, source: "requested", position: 1)
    assert_equal new_copy.id, item.song_id
  end
end
