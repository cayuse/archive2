require "test_helper"

class StationTest < ActiveSupport::TestCase
  setup do
    @owner = users(:admin)
    @copier = users(:moderator)
    @one, @two = songs(:one), songs(:two)
    @third = Song.create!(title: "Third", user: @owner, artist: @one.artist, processing_status: "completed")
    @station = Station.start!(@owner, song: @one)
  end

  def taste(station, user = station.user) = StationTaste.new(user: user, station: station)
  def say(station, song, kind, user: station.user) = StationFeedback.record!(user: user, station: station, song: song, kind: kind)

  test "named after its seed until someone names it" do
    assert_equal "Test Song Radio", @station.name
    runtime = @station.runtime!
    runtime.start_from!(@third)
    assert_equal "Third Radio", @station.reload.name
    assert_equal "Third Radio", runtime.reload.name
    @station.rename!("Evening")
    runtime.start_from!(@one)
    assert_equal "Evening", @station.reload.name
    assert_equal "Evening", runtime.reload.name
  end

  test "the same recipe is the same station; a tuned one is not" do
    assert_equal @station, Station.start!(@owner, song: @one)
    @station.write_settings!(@station.settings.merge("variety" => 0.9))
    other = Station.start!(@owner, song: @one)
    assert_not_equal @station, other
    assert_not_equal @station.recipe_digest, other.recipe_digest
    assert_not_equal @station, Station.start!(@owner, song: @one, name: "Named")
  end

  test "thumbs are a log: the newest one counts and clear takes it back" do
    say(@station, @one, "down")
    assert_equal "up", say(@station, @one, "up")
    assert_equal [ @one.id ], taste(@station).liked_ids
    assert_empty taste(@station).disliked_ids
    assert_nil say(@station, @one, "clear")
    assert_empty taste(@station).liked_ids
    assert_equal %w[down up clear], @station.station_feedbacks.order(:created_at).pluck(:kind)
  end

  test "a copy starts with what the original had learned and then goes its own way" do
    say(@station, @one, "up")
    say(@station, @two, "down")
    copy = travel(1.minute) { @station.copy_for!(@copier) }
    assert_equal @copier, copy.user
    assert_equal @station.seed_ids, copy.seed_ids
    assert_equal 0, copy.station_feedbacks.count                      # nothing was duplicated
    travel 2.minutes do
      assert_equal [ @one.id ], taste(copy).liked_ids
      assert_equal [ @two.id ], taste(copy).disliked_ids

      say(@station, @third, "up")                                     # the original moves on
      say(@station, @one, "down")
      assert_equal [ @one.id ], taste(copy).liked_ids                 # the copy does not follow
      assert_not_includes taste(copy).liked_ids, @third.id

      say(copy, @two, "up")                                           # the copier disagrees
      say(copy, @one, "clear")
      assert_equal [ @two.id ], taste(copy).liked_ids
      assert_empty taste(copy).disliked_ids
      assert_equal Set[@one.id, @two.id], taste(@station).disliked_ids.to_set   # the original is untouched
      assert_equal "up", StationFeedback.standing(user: @copier, song: @two, station: copy)
    end
  end

  test "a copy does not inherit the owner's banned songs" do
    say(@station, @one, "never")
    say(@station, @two, "tired")
    copy = @station.copy_for!(@copier)
    assert_empty taste(copy).blocked_ids
    assert_equal Set[@one.id, @two.id], taste(@station).blocked_ids
  end

  test "copying twice gives the same copy; a copy of a copy reads the whole chain up to each cutoff" do
    say(@station, @one, "up")
    copy = travel(1.minute) { @station.copy_for!(@copier) }
    assert_equal copy, @station.copy_for!(@copier)
    travel(2.minutes) { say(copy, @two, "up"); say(@station, @third, "up") }
    grand = travel(3.minutes) { copy.copy_for!(@owner, name: "Back again") }
    assert_equal 3, grand.lineage.size
    travel 4.minutes do
      say(copy, @third, "down")
      assert_equal Set[@one.id, @two.id], taste(grand).liked_ids.to_set
      assert_empty taste(grand).disliked_ids
    end
  end

  test "deleting an original keeps its copies working; the last copy takes the archive with it" do
    say(@station, @one, "up")
    runtime = @station.runtime!
    copy = travel(1.minute) { @station.copy_for!(@copier) }
    travel 2.minutes do
      @station.remove!
      assert_not Jukebox.exists?(runtime.id)
      assert @station.reload.archived_at
      assert_not_includes Station.for_user(@owner), @station
      assert_equal [ @one.id ], taste(copy).liked_ids
      copy.remove!
      assert_not Station.exists?(@station.id)
      assert_equal 0, StationFeedback.where(station_id: @station.id).count
    end
  end

  test "a copy of a copy still knows who made the station first, and what it has been taught" do
    say(@station, @one, "up")
    say(@station, @two, "down")
    copy = travel(1.minute) { @station.copy_for!(@copier) }
    grand = travel(2.minutes) { copy.copy_for!(@owner, name: "Mine again") }
    assert_equal @station, grand.original
    assert_equal @station, @station.original
    travel(3.minutes) { say(grand, @two, "clear") }
    travel 4.minutes do
      assert_equal({ up: 1, down: 0 }, grand.thumb_counts)
      assert_equal({ up: 1, down: 1 }, copy.thumb_counts)
    end
  end

  test "the first station cannot be removed" do
    assert_raises(ArgumentError) { Station.first_for(@owner).remove! }
  end

  test "a station from a playlist is linked to it, not a copy of it" do
    playlist = Playlist.create!(name: "Road Trip", user: @owner, is_public: true)
    playlist.add_song(@one)
    station = Station.start!(@owner, playlist: playlist, playlist_mode: "only")
    assert_equal "Road Trip Radio", station.name
    assert_equal [ @one.id ], station.playlist_song_ids(only: true)
    playlist.add_song(@two)
    assert_equal Set[@one.id, @two.id], station.playlist_song_ids(only: true).to_set
    assert_equal Set[@one.id, @two.id], station.runtime!.radio_allowed_song_ids.to_set
    inspired = Station.start!(@owner, playlist: playlist)
    assert_not_equal station, inspired
    assert_nil inspired.playlist_song_ids(only: true)
    assert_nil inspired.runtime!.radio_allowed_song_ids
    assert_equal [ [ playlist.id, "inspire" ] ], inspired.copy_for!(@copier).station_playlists.pluck(:playlist_id, :mode)
  end

  test "a party jukebox gets a private station on first use, or plays from one of the owner's" do
    party = Jukebox.create!(owner: @owner, name: "Party", guest_password: "pppp", fill_mode: "radio")
    assert_nil party.station
    assert_equal({}, party.radio_settings)
    party.update_radio_settings!("variety" => "0.2")
    assert party.station.implicit?
    assert_equal 0.2, party.radio_variety
    assert_not_includes Station.for_user(@owner), party.station
    implicit = party.station
    party.destroy
    assert_not Station.exists?(implicit.id)

    bound = Jukebox.create!(owner: @owner, name: "Bound", guest_password: "bbbb", fill_mode: "radio", station: @station)
    assert_equal @station.seed_ids, bound.radio_seed_ids
    bound.destroy
    assert Station.exists?(@station.id)
  end
end
