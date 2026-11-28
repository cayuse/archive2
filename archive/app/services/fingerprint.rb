# Chromaprint fingerprints: finding the other copies of a recording. Mirrors judge.py (ber,
# find_duplicates) in lib/audio_audit; RULES there hold the same numbers.
#
# A fingerprint is about 8 uint32 values a second for the first 120 s. Two files are the same
# recording when their fingerprints, slid against each other by up to MAX_SHIFT values, differ in at
# most MAX_BER of their bits, and their lengths agree (same_version?). Measured on this library: copies
# of one recording 0.00-0.20, different recordings (live, re-recorded) 0.30-0.50.
module Fingerprint
  MAX_BER = 0.20
  MAX_SHIFT = 24
  MIN_OVERLAP = 160
  MIN_HITS = 3          # sampled values two fingerprints must share before they are compared at all
  DUR_SECONDS = 4.0     # same version: lengths within max(DUR_SECONDS, DUR_FRACTION of the longer)
  DUR_FRACTION = 0.03
  QUERY_VALUES = 460    # values of the new fingerprint looked up in the index (judge.py: fp[:460])
  POP16 = Array.new(1 << 16) { |i| i.to_s(2).count("1") }.freeze

  module_function

  # The values stored in song_measurements.fingerprint_keys: every 4th from the 16th to the 420th
  # (judge.py: fp[16:420:4]), as signed int4.
  def keys(values) = signed((values[16...420] || []).each_slice(4).map(&:first).uniq)

  def signed(values) = values.map { |v| v >= 0x8000_0000 ? v - 0x1_0000_0000 : v }

  # Bit error rate of the best alignment, 1.0 when they never overlap enough.
  def ber(a, b, max_shift: MAX_SHIFT, min_overlap: nil)
    min_overlap ||= [ MIN_OVERLAP, (0.8 * [ a.size, b.size ].min).to_i ].min
    best = 1.0
    (-max_shift..max_shift).each do |sh|
      ia, ib = sh >= 0 ? [ sh, 0 ] : [ 0, -sh ]
      n = [ a.size - ia, b.size - ib ].min
      next if n < min_overlap || n <= 0
      diff = 0
      n.times do |k|
        v = a[ia + k] ^ b[ib + k]
        diff += POP16[v & 0xffff] + POP16[v >> 16]
      end
      e = diff / (32.0 * n)
      best = e if e < best
    end
    best
  end

  def same_version?(d1, d2)
    return false unless d1.to_f.positive? && d2.to_f.positive?
    (d1 - d2).abs <= [ DUR_SECONDS, DUR_FRACTION * [ d1, d2 ].max ].max
  end

  # Measurements of other songs that share at least MIN_HITS sampled values with these, most shared
  # first. The GIN index finds rows sharing any value; the count is taken on those few.
  def candidates(values, exclude_song_id: nil, limit: 100)
    query = signed(values.first(QUERY_VALUES).uniq)
    return SongMeasurement.none if query.empty?
    arr = ActiveRecord::Base.connection.quote("{#{query.join(',')}}")
    hits = "cardinality(array(select unnest(fingerprint_keys) intersect select unnest(#{arr}::int[])))"
    scope = SongMeasurement.where("fingerprint_keys && #{arr}::int[]").where.not(fingerprint: nil)
    scope = scope.where.not(song_id: exclude_song_id) if exclude_song_id
    SongMeasurement.from(scope.select("song_measurements.*, #{hits} AS hits"), :song_measurements)
                   .where("hits >= ?", MIN_HITS).order(hits: :desc).limit(limit)
  end

  # Song ids of the same recording at the same length (copies), and of the same recording at another
  # length (edits, not merged), with their error rates.
  def matches(measurement)
    values = measurement.fingerprint_values
    return { same: [], related: [] } if values.size < 40
    same, related = [], []
    found = candidates(values, exclude_song_id: measurement.song_id).to_a
    # remasters can share almost no exact values with the original, though their fingerprints still
    # agree (judge.py compares same-name pairs too): songs of the same title are always compared
    title = measurement.song&.title
    if title.present?
      named = SongMeasurement.joins(:song).where("lower(songs.title) = lower(?)", title)
                             .where.not(song_id: [ measurement.song_id, *found.map(&:song_id) ]).where.not(fingerprint: nil).limit(50)
      found.concat(named.to_a)
    end
    found.each do |other|
      ov = other.fingerprint_values
      next if ov.size < 40
      e = ber(values, ov)
      next if e > MAX_BER
      d_other = other.duration || other.song&.duration
      (same_version?(measurement.duration.to_f, d_other.to_f) ? same : related) << [ other.song_id, e.round(3) ]
    end
    { same: same, related: related }
  end
end
