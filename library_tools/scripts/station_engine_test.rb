# Checks of the station engine (SongRadio, StationTaste, StationFeedback, the jukebox fill) against
# a database with real library data. Everything it writes is rolled back at the end.
# Run:  rails runner station_engine_test.rb      (exits 1 if a check fails)
$fails = 0
def check(name, ok, detail = nil)
  $fails += 1 unless ok
  puts format("  %-4s %s%s", ok ? "ok" : "FAIL", name, detail ? "  (#{detail})" : "")
end
def stream(radio, n = 40) = radio.next_songs(n)

user = User.where(role: %w[admin moderator dj]).first or abort "no host user"
country = Genre.find_by(name: "Country")
seed = Song.joins(:artist, :audio_feature).where(genre: country, artists: { name: "George Strait" }).order(:title).first or abort "no seed"
puts "seed: #{seed.artist.name} - #{seed.title}"

ActiveRecord::Base.transaction do
  station = Jukebox.create_station!(user, name: "engine test", song: seed)
  radio = -> (**opts) { SongRadio.new(seed: seed, user: user, station: station, random: Random.new(5), **opts) }

  puts "flow"
  steady = stream(radio.(variety: 0)); e = steady.map { |s| s.audio_feature.energy }
  dynamic = stream(radio.(variety: 1)); d = dynamic.map { |s| s.audio_feature.energy }
  check "40 songs each", steady.size == 40 && dynamic.size == 40, "#{steady.size}/#{dynamic.size}"
  check "dynamic swings wider than steady", (d.max - d.min) > (e.max - e.min) + 0.1, format("steady %.2f, dynamic %.2f", e.max - e.min, d.max - d.min)
  high = stream(radio.(intensity: 0.9, variety: 0.1)).map { |s| s.audio_feature.energy }
  low = stream(radio.(intensity: -0.9, variety: 0.1)).map { |s| s.audio_feature.energy }
  check "intensity moves the level", high.sum / high.size > low.sum / low.size + 0.25, format("high %.2f, low %.2f", high.sum / high.size, low.sum / low.size)
  steps = d.each_cons(2).map { |a, b| (a - b).abs }
  check "no big energy jumps", steps.max < 0.45, format("max step %.2f", steps.max)

  puts "repeats"
  base = stream(radio.())
  check "no song twice", base.map(&:id).uniq.size == base.size
  check "no title twice", base.map { |s| SongRadio.title_key(s.title) }.uniq.size == base.size
  gaps = base.each_cons(SongRadio::ARTIST_GAP + 1).count { |w| w.last.artist_id && w[0...-1].map(&:artist_id).include?(w.last.artist_id) }
  check "artist gap of #{SongRadio::ARTIST_GAP}", gaps.zero?, "#{gaps} violations"
  twin = SongNeighbor.where("score >= ?", SongRadio::DUPLICATE_SCORE).joins("JOIN song_audio_features f ON f.song_id = song_neighbors.song_id").first
  if twin
    s = stream(SongRadio.new(seed: Song.find(twin.song_id), random: Random.new(2)), 30)
    check "a sound-duplicate of the seed never plays", s.none? { |x| x.id == twin.neighbor_id }
  end
  check "title_key folds versions", SongRadio.title_key("Hey Jude (Remastered 2009)") == SongRadio.title_key("Hey Jude - Live") && SongRadio.title_key("Hey Jude") == "heyjude"

  puts "thumbs are per station"
  victim = base.map(&:artist_id).compact.tally.max_by { |_, n| n }.first
  victim_songs = Song.where(artist_id: victim).joins(:audio_feature).limit(2).to_a
  before = base.count { |s| s.artist_id == victim }
  victim_songs.each { |s| StationFeedback.record!(user: user, jukebox: station, song: s, kind: "down") }
  taste = StationTaste.new(user: user, station: station)
  check "two downs take the artist off the station", taste.removed_artist_ids.include?(victim), Artist.find(victim).name
  after = stream(radio.())
  check "that artist no longer plays", after.none? { |s| s.artist_id == victim }, "before #{before}, after #{after.count { |s| s.artist_id == victim }}"
  other = Jukebox.create_station!(user, name: "engine test 2", song: seed)
  elsewhere = stream(SongRadio.new(seed: seed, user: user, station: other, random: Random.new(5)))
  check "but still plays on another station", elsewhere.any? { |s| s.artist_id == victim }
  station.keep_artist!(victim)
  check "keeping the artist puts them back", !StationTaste.new(user: user, station: station.reload).removed_artist_ids.include?(victim)

  puts "tired and never"
  t = after.first
  StationFeedback.record!(user: user, jukebox: station, song: t, kind: "tired")
  check "tired blocks on every station", StationTaste.new(user: user, station: other).blocked_ids.include?(t.id)
  check "tired is not a dislike", !StationTaste.new(user: user, station: station).disliked_ids.include?(t.id)
  StationFeedback.where(song_id: t.id, kind: "tired").update_all(expires_at: 1.minute.ago)
  check "tired wears off", !StationTaste.new(user: user, station: other).blocked_ids.include?(t.id)
  StationFeedback.record!(user: user, jukebox: station, song: t, kind: "never")
  check "never blocks everywhere", StationTaste.new(user: user, station: other).blocked_ids.include?(t.id)
  check "standing reads never", StationFeedback.standing(user: user, song: t, jukebox: station) == "never"
  StationFeedback.record!(user: user, jukebox: station, song: t, kind: "clear")
  check "clear takes it back", StationFeedback.standing(user: user, song: t, jukebox: station).nil?

  puts "taste"
  liked = after.select { |s| s.audio_feature.acousticness > 0.6 }.first(6)
  liked = after.first(6) if liked.size < 4
  liked.each { |s| StationFeedback.record!(user: user, jukebox: station, song: s, kind: "up") }
  taste = StationTaste.new(user: user, station: station.reload)
  check "taste vector is a unit vector", taste.vector && (Math.sqrt(taste.vector.sum { |x| x * x }) - 1).abs < 1e-6
  check "confidence grows with feedback", taste.confidence > 0.5, taste.confidence.round(2).to_s
  tasted = stream(radio.())
  emb = SongEmbedding.where(song_id: (after + tasted).map(&:id)).pluck(:song_id, :embedding).to_h
  close = ->(songs) { v = songs.filter_map { |s| emb[s.id] }.map { |e| e.each_with_index.sum { |x, i| x * taste.vector[i] } }; v.sum / v.size }
  check "stream moves toward the taste", close.(tasted) > close.(after), format("%.3f -> %.3f", close.(after), close.(tasted))
  check "liked songs are not blocked", (taste.blocked_ids & liked.map(&:id)).empty?
  skipper = tasted.last
  2.times { StationFeedback.record!(user: user, jukebox: station, song: skipper, kind: "skip", position: 4) }
  check "two early skips block a song", StationTaste.new(user: user, station: station).blocked_ids.include?(skipper.id)
  StationFeedback.record!(user: user, jukebox: station, song: tasted[-2], kind: "skip", position: 150)
  check "a late skip does not count", !StationTaste.new(user: user, station: station).skipped.key?(tasted[-2].id)

  puts "jukebox fill"
  c = Api::V1::JukeboxesController.new
  c.instance_variable_set(:@jukebox, station)
  station.update!(min_queue_length: 6, queue_refill_level: 8)
  c.send(:ensure_min_queue_length!)
  queue = station.ajb_queue_items.queue_order.includes(:song).map(&:song)
  check "fills to the refill level", queue.size == 8, queue.size.to_s
  check "seed first", queue.first.id == seed.id
  check "fill respects the removed artist rule", station.reload && queue.none? { |s| StationTaste.new(user: user, station: station).blocked_ids.include?(s.id) }
  extra = Song.joins(:audio_feature).where(genre: Genre.find_by(name: "Jazz")).first
  station.add_seed!(extra)
  check "adding a seed keeps both and retunes", station.radio_seed_ids == [ seed.id, extra.id ] && station.ajb_queue_items.where(source: "random").none?
  station.update_radio_settings!("intensity" => "0.5", "variety" => "0.2", "learn" => "false", "acousticness" => "0.6")
  check "settings stored", station.radio_intensity == 0.5 && station.radio_variety == 0.2 && !station.radio_learn? && station.radio_steer == { "acousticness" => 0.6 }
  station.update_radio_settings!("energy" => "-0.6")
  check "old energy dial becomes intensity", station.radio_intensity == -0.6
  station.update_radio_settings!("intensity" => "auto")
  check "intensity auto clears it", station.radio_intensity.nil?
  check "requests steer a station, not a party jukebox", station.requests_steer? && !Jukebox.new(session_id: "party").requests_steer?
  check "tuning payload", (StationTuning.new(station, user).as_json.keys & %i[seeds liked disliked tired never removed_artists learned_dials recent]).size == 8

  raise ActiveRecord::Rollback
end
puts $fails.zero? ? "\nall checks passed (rolled back)" : "\n#{$fails} check(s) FAILED (rolled back)"
exit($fails.zero? ? 0 : 1)
