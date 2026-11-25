require "test_helper"

class JukeboxStationTest < ActiveSupport::TestCase
  setup { @user = users(:admin) }

  test "everyone gets one first station, found again by its code" do
    station = Jukebox.station_for(@user)
    assert station.station? && station.radio?
    assert_equal station, Jukebox.station_for(@user)
    assert_equal station, Jukebox.first_station(@user)
    assert_nil Jukebox.first_station(users(:moderator))
  end

  test "a station made from a song is named after it and seeded with it" do
    song = songs(:one)
    station = Jukebox.create_station!(@user, song: song)
    assert_equal "Test Song Radio", station.name
    assert_equal [ song.id ], station.radio_seed_ids
    assert_equal [ song.id ], station.ajb_queue_items.pluck(:song_id)
    assert_equal 2, Jukebox.tap { |j| j.station_for(@user) }.stations_for(@user).count
  end

  test "seeds can be added and removed, capped at the maximum" do
    station = Jukebox.create_station!(@user, song: songs(:one))
    station.add_seed!(songs(:two))
    assert_equal [ songs(:one).id, songs(:two).id ], station.radio_seed_ids
    station.remove_seed!(songs(:one).id)
    assert_equal [ songs(:two).id ], station.radio_seed_ids
  end

  test "tuning is stored and read back" do
    station = Jukebox.station_for(@user)
    assert_nil station.radio_intensity
    assert_equal 0.5, station.radio_variety
    assert station.radio_learn?
    station.update_radio_settings!("intensity" => "0.4", "variety" => "0.9", "learn" => "false", "genre" => "strict", "happiness" => "-0.6", "energy" => "1")
    assert_equal 0.4, station.radio_intensity
    assert_equal 0.9, station.radio_variety
    assert_not station.radio_learn?
    assert_equal "strict", station.radio_genre_mode
    assert_equal({ "happiness" => -0.6 }, station.radio_steer)
    station.update_radio_settings!("energy" => "-0.6")          # an older client's energy dial
    assert_equal(-0.6, station.radio_intensity)
    station.update_radio_settings!("reset_steer" => "true")
    assert_nil station.radio_intensity
    assert_empty station.radio_steer
  end

  test "requests steer a personal station but not a party jukebox unless asked" do
    assert Jukebox.station_for(@user).requests_steer?
    party = Jukebox.new(session_id: "party", radio_settings: {})
    assert_not party.requests_steer?
    party.radio_settings = { "requests_steer" => true }
    assert party.requests_steer?
  end
end
