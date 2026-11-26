require "test_helper"

class StationFeedbackTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @song = songs(:one)
    @jukebox = Jukebox.create_station!(@user, name: "A")
    @station = @jukebox.station
    @other = Jukebox.create_station!(@user, name: "B").station
  end

  test "a thumb belongs to the station it was given on" do
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "down")
    assert_equal "down", StationFeedback.standing(user: @user, song: @song, station: @station)
    assert_nil StationFeedback.standing(user: @user, song: @song, station: @other)
  end

  test "a new thumb replaces the old one on that station" do
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "down")
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "up")
    assert_equal "up", StationFeedback.standing(user: @user, song: @song, station: @station)
    assert_equal [ @song.id ], StationTaste.new(user: @user, station: @station).liked_ids
  end

  test "tired applies to every station, expires, and is not a dislike" do
    assert_equal "tired", StationFeedback.record!(user: @user, station: @station, song: @song, kind: "tired")
    assert_equal "tired", StationFeedback.standing(user: @user, song: @song, station: @other)
    taste = StationTaste.new(user: @user, station: @other)
    assert_includes taste.blocked_ids, @song.id
    assert_empty taste.disliked_ids
    travel StationFeedback::TIRED_FOR + 1.hour do
      assert_nil StationFeedback.standing(user: @user, song: @song, station: @other)
      assert_not_includes StationTaste.new(user: @user, station: @other).blocked_ids, @song.id
    end
  end

  test "never applies everywhere and clear takes it back" do
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "never")
    assert_includes StationTaste.new(user: @user, station: @other).blocked_ids, @song.id
    assert_nil StationFeedback.record!(user: @user, station: @other, song: @song, kind: "clear")
    assert_empty StationTaste.new(user: @user, station: @other).blocked_ids
  end

  test "two early skips block a song, late skips do not count" do
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "skip", position: 200)
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "skip", position: 5)
    assert_not_includes StationTaste.new(user: @user, station: @station).blocked_ids, @song.id
    StationFeedback.record!(user: @user, station: @station, song: @song, kind: "skip", position: 9)
    assert_includes StationTaste.new(user: @user, station: @station).blocked_ids, @song.id
  end

  test "two downs with no ups take the artist off that station only, and keeping puts them back" do
    second = Song.create!(title: "Second", user: @user, artist: @song.artist, processing_status: "completed")
    [ @song, second ].each { |s| StationFeedback.record!(user: @user, station: @station, song: s, kind: "down") }
    assert_includes StationTaste.new(user: @user, station: @station).removed_artist_ids, @song.artist_id
    assert_empty StationTaste.new(user: @user, station: @other).removed_artist_ids
    @jukebox.keep_artist!(@song.artist_id)
    assert_empty StationTaste.new(user: @user, station: @station.reload).removed_artist_ids
  end

  test "rate! keeps the old 1 / -1 / 0 contract" do
    assert_equal 1, StationFeedback.rate!(user: @user, song: @song, value: 1, station: @station)
    assert_equal(-1, StationFeedback.rate!(user: @user, song: @song, value: "-1", station: @station))
    assert_equal 0, StationFeedback.rate!(user: @user, song: @song, value: 0, station: @station)
    assert_nil StationFeedback.standing(user: @user, song: @song, station: @station)
    assert_empty StationTaste.new(user: @user, station: @station).disliked_ids
  end

  test "unknown kinds are refused" do
    assert_raises(ArgumentError) { StationFeedback.record!(user: @user, station: @station, song: @song, kind: "bogus") }
  end
end
