require "test_helper"

class LibraryQualityControllerTest < ActionDispatch::IntegrationTest
  PRINT = Random.new(7).then { |r| Array.new(900) { r.rand(1 << 32) } }.freeze

  def measured(song, **m)
    SongMeasurement.create!({ song: song, measure_version: 2, score_version: 1, verdict: "ok", kbps: 192, eff_khz: 16.0,
                              duration: 200.0, measured_at: Time.current, fingerprint_values: PRINT }.merge(m))
    song
  end

  setup do
    @old = measured(songs(:one), verdict: "bad", problems: [ { "level" => "bad", "text" => "2 damaged spots (loud blowouts) at 0:31, 1:32" } ])
    SongIssue.record_quality!(@old, @old.measurement, source: "audit")
  end

  test "only admins see the page" do
    get library_quality_path
    assert_redirected_to login_path
    sign_in users(:moderator)
    get library_quality_path
    assert_redirected_to root_path
  end

  test "the wanted list shows broken songs still playing; merged copies can be restored" do
    sign_in users(:admin)
    get library_quality_path
    assert_response :success
    assert_select "td", text: /loud blowouts/

    better = measured(Song.create!(title: "Better copy", album: albums(:one)), lossless: true, bits: 16, sample_rate: 44_100, kbps: 950, eff_khz: 21.0)
    assert_equal "better", SongMerger.new(log: Logger.new(IO::NULL)).merge(better).outcome
    get library_quality_path
    assert_select "td", text: /loud blowouts/, count: 0
    assert_select "button", text: "Restore"

    merge = SongMerge.find_by!(song: @old)
    post restore_library_quality_merge_path(merge)
    assert_redirected_to library_quality_path
    assert_not @old.reload.hidden?
  end

  test "hidden copies stay out of song lists and search, but the album shows the whole tracklist" do
    better = measured(Song.create!(title: "Better copy", album: albums(:one)), lossless: true, bits: 16, sample_rate: 44_100, kbps: 950, eff_khz: 21.0)
    SongMerger.new(log: Logger.new(IO::NULL)).merge(better)
    sign_in users(:admin)
    get songs_path
    assert_select "a.song-title", text: @old.title, count: 0
    get album_path(@old.album)
    assert_select "a.song-title", text: @old.title
    assert_select "small", text: /plays as/
  end
end
