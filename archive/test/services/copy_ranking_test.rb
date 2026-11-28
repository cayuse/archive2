require "test_helper"

class CopyRankingTest < ActiveSupport::TestCase
  def m(**attrs) = SongMeasurement.new({ verdict: "ok", lossless: false, kbps: 256, eff_khz: 19.0 }.merge(attrs))

  CASES = {
    "intact beats broken" => [ { verdict: "ok", kbps: 128, eff_khz: 16.0 }, { verdict: "bad", lossless: true, bits: 16, sample_rate: 44_100, kbps: 900, eff_khz: 21.0 } ],
    "lossless beats lossy" => [ { lossless: true, bits: 16, sample_rate: 44_100, kbps: 900, eff_khz: 21.0 }, { kbps: 320, eff_khz: 20.0 } ],
    "hi-res beats CD" => [ { lossless: true, bits: 24, sample_rate: 48_000, kbps: 1700, eff_khz: 21.0 }, { lossless: true, bits: 16, sample_rate: 44_100, kbps: 950, eff_khz: 21.0 } ],
    "a higher cutoff beats a lower one" => [ { kbps: 192, eff_khz: 19.0 }, { kbps: 320, eff_khz: 16.0 } ],
    "the bitrate tier decides when the cutoff is the same" => [ { kbps: 256, eff_khz: 19.5 }, { kbps: 192, eff_khz: 19.5 } ],
    "weak beats flawed" => [ { verdict: "weak", kbps: 96, eff_khz: 14.0 }, { verdict: "flawed", kbps: 320, eff_khz: 20.0 } ]
  }.freeze

  CASES.each do |name, (better, worse)|
    test "#{name}, and is worth a swap" do
      assert CopyRanking.better?(m(**better), m(**worse))
      assert_not CopyRanking.better?(m(**worse), m(**better))
    end
  end

  test "small differences are not worth a swap: 257k against 256k, 20 kHz against 19.6" do
    assert_not CopyRanking.better?(m(kbps: 257, eff_khz: 20.0), m(kbps: 256, eff_khz: 19.6))
    assert_not CopyRanking.better?(m(kbps: 256), m(kbps: 256))
  end

  test "compilations rank below the artist's own album, in several languages" do
    %w[Greatest\ Hits Grandes\ Éxitos Лучшее Збірка 베스트\앨범 Best\ of\ the\ 80s].each do |title|
      assert_match CopyRanking::COMPILATION, title.tr("\\", "")
    end
    %w[Dandelion Группа\ крови Different\ Man].each { |title| assert_no_match CopyRanking::COMPILATION, title.tr("\\", "") }
  end

  test "the order agrees with judge.py strength_of, the rules the library audit used" do
    rows = CASES.values.flatten.map { |a| m(**a) }
    ruby = rows.map { |x| CopyRanking.strength(x).first(CopyRanking::MEANINGFUL) }
    evs = rows.map do |x|
      { verdict: x.verdict, lossless: x.lossless, res: x.lossless ? [ x.bits, x.sample_rate ] : [ 0, 0 ], eff_khz: x.eff_khz, kbps: x.kbps }
    end
    script = <<~PY
      import json, sys
      sys.path.insert(0, #{Rails.root.join('lib/audio_audit').to_s.to_json})
      from judge import strength_of
      evs = json.load(sys.stdin)
      print(json.dumps([list(strength_of(dict(e, res=tuple(e["res"])), 0)[:5]) for e in evs]))
    PY
    out, err, status = Open3.capture3("python3", "-c", script, stdin_data: evs.to_json)
    assert status.success?, err
    python = JSON.parse(out).map { |s| [ s[0], s[1] ? 1 : 0, s[2], s[3].to_f, s[4] ] }
    assert_equal python, ruby.map { |s| [ s[0], s[1], s[2], s[3].to_f, s[4] ] }
  end
end
