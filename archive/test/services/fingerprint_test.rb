require "test_helper"

class FingerprintTest < ActiveSupport::TestCase
  def print_of(seed, n = 900) = Random.new(seed).then { |r| Array.new(n) { r.rand(1 << 32) } }

  # a copy of the same recording, as a different encode prints it: most values identical, some with a
  # few bits changed (copies in the library measure 0.00-0.20)
  def copy_of(values, share: 0.3, flips: 3, seed: 1)
    r = Random.new(seed)
    values.map { |v| r.rand < share ? flips.times.reduce(v) { |x, _| x ^ (1 << r.rand(32)) } : v }
  end

  test "identical, re-encoded and shifted copies are the same recording; different recordings are not" do
    a = print_of(1)
    assert_equal 0.0, Fingerprint.ber(a, a)
    assert_in_delta 0.3 * 3 / 32.0, Fingerprint.ber(a, copy_of(a)), 0.01
    assert_equal 0.0, Fingerprint.ber(a, a.drop(7)), "a copy that starts a little later still lines up"
    assert_in_delta 0.5, Fingerprint.ber(a, print_of(2)), 0.03
  end

  test "keys are every fourth value from the 16th, as signed int4 for Postgres" do
    values = Array.new(500) { |i| i.even? ? 0xFFFF_FFFF - i : i }
    keys = Fingerprint.keys(values)
    assert_equal values[16...420].each_slice(4).map(&:first).uniq.size, keys.size
    assert keys.all? { |k| k.between?(-2**31, 2**31 - 1) }
    assert_equal(-17, Fingerprint.signed([ 0xFFFF_FFFF - 16 ]).first)
  end

  test "lengths must agree for two copies to be the same version" do
    assert Fingerprint.same_version?(200.0, 203.5)
    assert Fingerprint.same_version?(600.0, 615.0), "3% of a long track"
    assert_not Fingerprint.same_version?(200.0, 260.0), "an extended mix is a different version"
  end

  test "matches finds copies through the index, in any order of shifts, and leaves other recordings out" do
    base = print_of(3)
    songs = { same: songs(:one), shifted: songs(:two), other: Song.create!(title: "Other") }
    new_song = Song.create!(title: "New")
    { same: copy_of(base), shifted: copy_of(base.drop(5), seed: 2), other: print_of(4) }.each do |k, values|
      SongMeasurement.create!(song: songs[k], measure_version: 2, score_version: 1, verdict: "ok", duration: 200.0,
                              measured_at: Time.current, fingerprint_values: values)
    end
    m = SongMeasurement.create!(song: new_song, measure_version: 2, score_version: 1, verdict: "ok", duration: 201.0,
                                measured_at: Time.current, fingerprint_values: base)
    found = Fingerprint.matches(m)
    assert_equal [ songs[:same].id, songs[:shifted].id ].sort, found[:same].map(&:first).sort
    assert_empty found[:related]
  end
end
