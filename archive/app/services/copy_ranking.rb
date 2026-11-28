# Which of several copies of one recording should play. Mirrors judge.py strength_of in
# lib/audio_audit (keep the two in step; test/services/copy_ranking_test.rb holds them to it):
#
#   1. intact beats weak beats flawed beats bad
#   2. real lossless beats lossy (a "lossless" file made from a lossy one counts as lossy)
#   3. resolution, between lossless copies: 24-bit / 48 kHz over 16-bit / 44.1 kHz
#   4. where the music really stops, to the half kHz; 19.5 kHz and up count as equal
#   5. bitrate tier: 256+, 192+, 128+, below
#   -- a new copy takes over only when it wins on 1-5; below that a difference is not worth a swap
#   6. the artist's own album over a hits package or compilation
#   7. bitrate, then plays
module CopyRanking
  RANK = { "ok" => 3, "weak" => 2, "flawed" => 1, "bad" => 0 }.freeze
  MEANINGFUL = 5
  # hits packages and compilations, in the languages the library holds most (judge.py COMPILATION)
  COMPILATION = Regexp.new([
    "greatest", "best of", '\bhits\b', "collection", "essential", "anthology", '\bgold\b', "now that", 'top \d', "radio",
    "promo only", "sampler", '\bvol(ume)?\b', "classics", "ultimate", "totally", "100%", "compilation", "various",
    "soundtrack", '\bdisco\b.*\d', '\d+ (years|años)', "grandes [eé]xitos", "lo mejor", "éxitos", "exitos", "meilleur",
    "plus grands succès", "сборник", "лучшее", "лучшие песни", "избранное", "збірка", "найкращ", "베스트", "히트", "ベスト",
    "精选", "精選", "金曲"
  ].join("|"), Regexp::IGNORECASE)

  module_function

  def kbps_tier(k)
    k = k.to_i
    k >= 256 ? 3 : k >= 192 ? 2 : k >= 128 ? 1 : 0
  end

  def strength(m, pref: 0.0, plays: 0)
    eff = ((m.eff_khz.to_f * 2).round(half: :even) / 2.0)
    [ RANK.fetch(m.verdict, 0), m.lossless ? 1 : 0, m.lossless ? [ m.bits || 16, m.sample_rate || 44_100 ] : [ 0, 0 ],
      [ 19.5, eff ].min, kbps_tier(m.kbps), pref, m.kbps.to_i, plays ]
  end

  # true when measurement a beats b by enough to take over
  def better?(a, b) = (strength(a).first(MEANINGFUL) <=> strength(b).first(MEANINGFUL)) == 1

  # The artist's share of the album, less a penalty for hits packages and compilations.
  def album_preference(song)
    return 0.0 unless song.album_id
    counts = Song.where(album_id: song.album_id).group(:artist_id).count
    share = counts[song.artist_id].to_f / [ counts.values.sum, 1 ].max
    (share - (song.album&.title.to_s.match?(COMPILATION) ? 0.6 : 0)).round(2)
  end

  def full_strength(song)
    strength(song.measurement, pref: album_preference(song), plays: song.ajb_played_songs.count)
  end

  # Why measurement b beats a, in words (judge.py why_worse).
  def reasons(b, a)
    out = []
    out << "the other copy is #{a.verdict}" if RANK[b.verdict] > RANK[a.verdict]
    if b.lossless && !a.lossless
      out << "lossless against lossy"
    elsif b.lossless && ([ b.bits.to_i, b.sample_rate.to_i ] <=> [ a.bits.to_i, a.sample_rate.to_i ]) == 1
      out << "#{b.bits}-bit/#{format('%g', b.sample_rate / 1000.0)} kHz against #{a.bits}-bit/#{format('%g', a.sample_rate.to_i / 1000.0)} kHz"
    end
    if [ 19.5, b.eff_khz.to_f ].min > [ 19.5, a.eff_khz.to_f ].min + 0.4
      out << "goes to #{format('%g', b.eff_khz)} kHz against #{format('%g', a.eff_khz.to_f)}"
    end
    out << "#{b.kbps} kbps against #{a.kbps}" if out.empty? && kbps_tier(b.kbps) > kbps_tier(a.kbps)
    out
  end
end
