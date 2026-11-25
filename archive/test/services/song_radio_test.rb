require "test_helper"

# A small made-up library: a seed with a ring of sound-alikes, so the radio's rules can be checked
# without real audio data. (The checks against the real library are in
# library_tools/scripts/station_engine_test.rb.)
class SongRadioTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @seed = make_song("Seed", energy: 0.5)
    @near = (1..12).map { |i| make_song("Near #{i}", energy: 0.1 + 0.07 * i, artist: (i % 4).zero? ? artists(:one) : nil) }
    @near.each_with_index { |s, i| link(@seed, s, 0.95 - 0.005 * i, i + 1) }
    @near.each_cons(2) { |a, b| link(a, b, 0.9, 1) }   # most songs here have no artist, so the artist gap does not bite
  end

  test "plays the seed's neighbours without repeats" do
    songs = SongRadio.new(seed: @seed, random: Random.new(1)).next_songs(8)
    assert_equal 8, songs.size
    assert_equal songs.map(&:id).uniq, songs.map(&:id)
    assert_not_includes songs, @seed
  end

  test "an unanalysed seed gives nothing" do
    assert_empty SongRadio.new(seed: songs(:one)).next_songs(5)
  end

  test "a second copy or another version of a recent song is skipped" do
    copy = make_song("Near 1 (Remastered)", energy: 0.2)
    twin = make_song("Different Title", energy: 0.2)
    link(@seed, copy, 0.96, 20)
    link(@near.first, twin, 0.999, 20)
    songs = SongRadio.new(seed: @seed, exclude_ids: [ @near.first.id ], random: Random.new(1)).next_songs(12)
    assert_not_includes songs, copy, "same title as a recent song"
    assert_not_includes songs, twin, "sound-duplicate of a recent song"
  end

  test "thumbed-down songs and removed artists do not play on that station" do
    station = Jukebox.create_station!(@user, name: "t")
    @near.select { |s| s.artist_id == artists(:one).id }.first(2).each do |s|
      StationFeedback.record!(user: @user, jukebox: station, song: s, kind: "down")
    end
    songs = SongRadio.new(seed: @seed, user: @user, station: station, random: Random.new(1)).next_songs(12)
    assert songs.any?
    assert songs.none? { |s| s.artist_id == artists(:one).id }
    elsewhere = SongRadio.new(seed: @seed, user: @user, random: Random.new(1)).next_songs(12)
    assert elsewhere.any? { |s| s.artist_id == artists(:one).id }
  end

  test "intensity moves the stream up and down in energy" do
    mean = ->(i) { e = SongRadio.new(seed: @seed, intensity: i, variety: 0, random: Random.new(1)).next_songs(4).map { |s| s.audio_feature.energy }; e.sum / e.size }
    assert_operator mean.(0.9), :>, mean.(-0.9) + 0.2
  end

  test "the energy target rises and falls with variety and stays flat without it" do
    flat = SongRadio.new(seed: @seed, variety: 0, intensity: 0)
    assert_equal [ 0.5 ], (0..9).map { |slot| flat.target_energy(slot).round(3) }.uniq
    wavy = SongRadio.new(seed: @seed, variety: 1, intensity: 0)
    targets = (0..9).map { |slot| wavy.target_energy(slot) }
    assert_in_delta 2 * SongRadio::WAVE_SWING, targets.max - targets.min, 0.03
    assert_equal targets.max, targets[(SongRadio::WAVE_LENGTH * SongRadio::WAVE_PEAK).round]
  end

  test "title_key reduces versions of a title to one key" do
    assert_equal "heyjude", SongRadio.title_key("Hey Jude (Remastered 2009)")
    assert_equal "heyjude", SongRadio.title_key("Hey Jude - Live at the BBC")
    assert_nil SongRadio.title_key("(untitled)")
  end

  private

  def make_song(title, energy:, artist: nil)
    song = Song.create!(title: title, user: @user, artist: artist, processing_status: "completed")
    dials = SongAudioFeature::DIALS.to_h { |d| [ d, 0.5 ] }.merge("energy" => energy, "speech" => 0.1)
    SongAudioFeature.create!(dials.merge(song: song))
    song
  end

  def link(from, to, score, rank)
    SongNeighbor.create!(song: from, neighbor: to, score: score, rank: rank)
  end
end
