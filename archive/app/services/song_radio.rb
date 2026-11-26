# Builds an endless-style stream from one or more seed songs: "play things that sound like this",
# shaped the way a station is programmed rather than as a flat list of sound-alikes.
#
# It walks the precomputed sounds-like links (song_neighbors). Each pick is drawn from songs near
# one of the seeds (keeps the theme; seeds take turns), near the song before it (lets the stream
# drift) and near songs the listener liked.
#
# What it takes into account:
#   * sound similarity, one and two steps out from the seeds
#   * flow: a target energy that rises and falls over WAVE_LENGTH songs around the station's
#     +intensity+ (nil = the seeds' own level), swinging by +variety+ (0 = steady, 1 = dynamic),
#     with a limit on how far energy may jump between neighbouring songs
#   * no repeats, no second copy or other version of something just played, a gap before the same
#     artist comes round again
#   * no spoken word unless a seed is spoken word
#   * steer:      dials to lean on, each -1.0..1.0, relative to the seed, e.g. { acousticness: -1 }
#   * genre_mode: "any" (default), "adjacent" (the seeds' genres plus genres that sound like them
#                 in this library, see GenreAffinity) or "strict" (the seeds' genres only)
#   * user / station: what the listener told this station (StationFeedback, StationTaste). Blocked
#                 songs never play, artists taken off the station never play, and candidates are
#                 pulled toward the station's taste and learned dial leanings
#   * allowed_ids: only these songs may be picked (e.g. a jukebox's assigned playlists)
#
#   SongRadio.new(seed: song).next_songs(20)
#   SongRadio.new(seed: song, user: current_user, intensity: -0.5, variety: 0.2).next_songs(10)
#   SongRadio.for_jukebox(jukebox)&.next_songs(4)
class SongRadio
  DIALS = SongAudioFeature::DIALS
  STEER_DIALS = DIALS - %w[energy]   # energy is run by intensity and the flow, not by a lean
  GENRE_MODES = %w[any adjacent strict].freeze
  SPEECH_CUTOFF = 0.96      # top 4% of the "speech" dial is audiobooks and talking
  ARTIST_GAP = 4            # songs before an artist may come round again
  POOL = 8                  # choose at random among this many best candidates
  MAX_SEEDS = 6
  SEED_WEIGHT = 1.0
  DRIFT_WEIGHT = 0.9
  LIKED_WEIGHT = 0.88
  SECOND_STEP = 0.97        # discount on a neighbour of a neighbour
  LIKED_SOURCES = 2         # liked songs mixed into each pick's sources
  DUPLICATE_SCORE = 0.995   # this close in sound = the same recording (another rip, a reissue)
  STEER_STRENGTH = 0.5
  LEARN_STRENGTH = 0.3
  DIAL_SPAN = 0.4           # a lean stops paying beyond this distance from the seed's dial
  TASTE_STRENGTH = 0.05     # per standard deviation of closeness to the station's taste
  TASTE_POOL = 150          # best candidates that get a taste score
  FLOW_STRENGTH = 0.4       # cost per unit of distance from the slot's target energy
  STEP_STRENGTH = 0.6       # cost per unit of energy jump beyond the allowed step
  WAVE_LENGTH = 10          # songs per rise and fall
  WAVE_PEAK = 0.6           # share of the wave spent building; the rest releases
  WAVE_SWING = 0.28         # energy swing either side of centre at variety 1
  SKIP_PENALTY = 0.08       # skipped early once on this station
  SOFT_ARTIST_PENALTY = 0.08 # artist with more thumbs down than up on this station

  attr_reader :trace, :taste

  # The radio for a jukebox's next auto-fill, or nil when it has nothing to start from.
  def self.for_jukebox(jukebox, genre_mode: nil, exclude_ids: nil)
    queue = jukebox.ajb_queue_items
    request_id = queue.requested.order(position: :desc).pick(:song_id) ||
                 jukebox.ajb_played_songs.order(played_at: :desc).limit(4).select(&:requested?).first&.song_id
    last_id = queue.order(position: :desc).pick(:song_id) || jukebox.ajb_played_songs.order(played_at: :desc).pick(:song_id)
    station = jukebox.station
    seed_ids = jukebox.radio_seed_ids
    # a station started from playlists: a fresh handful of their songs joins the seeds each time,
    # so over a run of songs the station covers the whole playlist's sound
    if station && seed_ids.size < MAX_SEEDS
      pool = station.playlist_song_ids - seed_ids
      seed_ids += pool.sample(MAX_SEEDS - seed_ids.size - (request_id ? 1 : 0)) if pool.any?
    end
    # no saved seeds (a party jukebox, or a station from before seeds existed): follow the newest
    # request ever made, else the last song in line
    request_id ||= jukebox.ajb_played_songs.where(source: "requested").order(played_at: :desc).pick(:song_id) if seed_ids.empty?
    ids = ([ request_id ] + seed_ids).compact.uniq
    ids = [ last_id ].compact if ids.empty?
    songs = Song.where(id: ids).index_by(&:id)
    anchors = ids.filter_map { |id| songs[id] }
    return nil if anchors.empty?

    played = jukebox.ajb_played_songs
    new(seed: anchors.first, seeds: anchors.drop(1), after: last_id, exclude_seeds: false,
        exclude_ids: exclude_ids || (played.recent(50).pluck(:song_id) + queue.pluck(:song_id)),
        allowed_ids: jukebox.radio_allowed_song_ids,
        user: jukebox.owner, station: station, steer: jukebox.radio_steer,
        genre_mode: genre_mode || jukebox.radio_genre_mode,
        intensity: jukebox.radio_intensity, variety: jukebox.radio_variety, learn: jukebox.radio_learn?,
        position: played.count + queue.count)
  end

  def initialize(seed:, seeds: [], after: nil, exclude_ids: [], exclude_seeds: true, steer: {}, allowed_ids: nil,
                 genre_mode: "any", user: nil, station: nil, intensity: nil, variety: 0.5, position: 0,
                 learn: true, random: Random.new)
    @seed = seed
    @anchors = ([ seed ] + Array(seeds)).compact.uniq(&:id).first(MAX_SEEDS)
    @after = after
    recent = exclude_ids.map(&:to_s).uniq
    @exclude = Set.new(recent)
    @anchors.each { |a| @exclude << a.id.to_s } if exclude_seeds
    @allowed = allowed_ids && Set.new(allowed_ids.map(&:to_s))
    @steer = steer.to_h.transform_keys(&:to_s).slice(*STEER_DIALS)
                  .transform_values { |v| v.to_f.clamp(-1.0, 1.0) }.reject { |_, v| v.zero? }
    @intensity = intensity.nil? || intensity.to_s.empty? ? nil : intensity.to_f.clamp(-1.0, 1.0)
    @variety = variety.to_f.clamp(0.0, 1.0)
    @position = position.to_i
    @genres = allowed_genres(GENRE_MODES.include?(genre_mode.to_s) ? genre_mode.to_s : "any")
    @random = random
    @taste = StationTaste.new(user: user, station: station, learn: learn)
    @taste.blocked_ids.each { |id| @exclude << id.to_s }
    @second_step = {}
    @embeddings = {}
    @credit_checked = {}
    @trace = []
    load_recent(recent + (exclude_seeds ? @anchors.map { |a| a.id.to_s } : []))
  end

  # Returns up to +count+ songs, in play order. Empty if the seed has not been analysed.
  def next_songs(count = 20)
    anchor_dials = @anchors.to_h { |a| [ a.id, dials_for(a.id) ] }.compact
    return [] if anchor_dials[@seed.id].nil?

    @centre = centre_energy(anchor_dials.values)
    allow_speech = anchor_dials.values.any? { |d| d["speech"].to_f >= SPEECH_CUTOFF }
    usable = @anchors.select { |a| anchor_dials[a.id] }
    current_id = @after || @seed.id
    current_dials = (@after && dials_for(@after)) || anchor_dials[@seed.id]
    recent_artists = Song.where(id: [ current_id ]).pluck(:artist_id).compact
    picked = []

    count.times do |i|
      slot = @position + i
      anchor = usable[slot % usable.size]
      context = { dials: current_dials, anchor_dials: anchor_dials[anchor.id], target: target_energy(slot),
                  allow_speech: allow_speech, blocked_artists: recent_artists.last(ARTIST_GAP) }
      sources = { anchor.id => SEED_WEIGHT, current_id => DRIFT_WEIGHT }
      @taste.liked_ids.sample(LIKED_SOURCES, random: @random).each { |id| sources[id] ||= LIKED_WEIGHT }
      cands = candidates(sources, anchor, context)
      if cands.empty? && (usable.size > 1 || picked.any?)
        # ran dry (tight genre or playlist limits): widen to every seed and everything picked so far
        wide = (usable.map(&:id) + picked.last(12)).to_h { |id| [ id, DRIFT_WEIGHT ] }
        cands = candidates(wide, anchor, context)
      end
      choice = pick(cands)
      break unless choice

      picked << choice["id"]
      remember(choice)
      @trace << choice.slice("id", "weight", "base", "energy", "notes").merge("slot" => slot, "target" => context[:target].round(3))
      recent_artists << choice["artist_id"] if choice["artist_id"]
      current_id = choice["id"]
      current_dials = choice.slice(*DIALS)
    end

    songs = Song.includes(:artist, :album, :genre, :audio_feature).where(id: picked).index_by(&:id)
    picked.filter_map { |id| songs[id] }
  end

  # Target energy (0..1 percentile) for the song in this slot: the station's centre plus a wave
  # that builds for WAVE_PEAK of its length and then releases.
  def target_energy(slot)
    swing = WAVE_SWING * @variety
    centre = (@centre || 0.5).clamp(swing + 0.03, 0.97 - swing)
    phase = (slot % WAVE_LENGTH) / WAVE_LENGTH.to_f
    shape = if phase < WAVE_PEAK
      -Math.cos(Math::PI * phase / WAVE_PEAK)
    else
      Math.cos(Math::PI * (phase - WAVE_PEAK) / (1.0 - WAVE_PEAK))
    end
    centre + swing * shape
  end

  # Titles differ between rips and reissues of one recording ("Song (Remastered 2009)", "Song - Live").
  # This reduces a title to its core so those compare equal.
  def self.title_key(title)
    key = title.to_s.downcase.gsub(/[\(\[][^\)\]]*[\)\]]/, " ").sub(/\s+-\s+.*\z/, " ").gsub(/[^[:alnum:]]+/, "")
    key.presence
  end

  private

  def dials_for(song_id)
    SongAudioFeature.where(song_id: song_id).pick(*DIALS)&.then { |row| DIALS.zip(row).to_h }
  end

  def centre_energy(dial_rows)
    return 0.5 + 0.42 * @intensity if @intensity
    base = dial_rows.sum { |d| d["energy"].to_f } / dial_rows.size
    base + 0.25 * @taste.learned_dials["energy"].to_f
  end

  def max_step
    0.18 + 0.22 * @variety
  end

  # nil = any genre
  def allowed_genres(mode)
    genre_ids = @anchors.map(&:genre_id).compact.uniq
    return nil if mode == "any" || genre_ids.empty?

    ids = genre_ids.dup
    # adjacent also lets in songs with no genre tag: they got here by sounding like the seed
    ids += GenreAffinity.where(genre_id: genre_ids).pluck(:related_genre_id) + [ nil ] if mode == "adjacent"
    Set.new(ids)
  end

  # Titles and recordings just played or lined up, and exact sound-duplicates of them: a second
  # copy of the same recording must not turn up two songs later.
  def load_recent(ids)
    @recent_titles = Set.new
    @recent_recordings = Set.new
    return if ids.empty?
    Song.where(id: ids).pluck(:title, :musicbrainz_recording_id).each do |title, recording|
      key = self.class.title_key(title)
      @recent_titles << key if key
      @recent_recordings << recording if recording
    end
    SongNeighbor.where(song_id: ids).where("score >= ?", DUPLICATE_SCORE).pluck(:neighbor_id).each { |id| @exclude << id.to_s }
  end

  def remember(choice)
    @exclude << choice["id"].to_s
    @recent_titles << choice["title_key"] if choice["title_key"]
    @recent_recordings << choice["recording"] if choice["recording"]
    SongNeighbor.where(song_id: choice["id"]).where("score >= ?", DUPLICATE_SCORE).pluck(:neighbor_id).each { |id| @exclude << id.to_s }
  end

  COLUMNS = [ "song_neighbors.song_id", "songs.id", "songs.artist_id", "songs.genre_id", "songs.title",
              "songs.musicbrainz_recording_id", "song_neighbors.score" ].freeze

  def neighbour_rows(from_ids)
    SongNeighbor.where(song_id: from_ids)
                .joins("JOIN songs ON songs.id = song_neighbors.neighbor_id")
                .joins("JOIN song_audio_features f ON f.song_id = song_neighbors.neighbor_id")
                .pluck(*COLUMNS.map { |c| Arel.sql(c) }, *DIALS.map { |d| Arel.sql("f.#{d}") })
  end

  def to_row(id, artist_id, genre_id, title, recording, dials, base)
    DIALS.zip(dials).to_h.merge("id" => id, "artist_id" => artist_id, "genre_id" => genre_id,
                                "title_key" => self.class.title_key(title), "recording" => recording, "base" => base)
  end

  # Songs two steps out from a seed (neighbours of its neighbours), scored by the product of the two
  # links. Gives each pick a few hundred candidates instead of thirty, which is what lets flow, taste
  # and genre limits choose rather than take whatever is left. Cached per seed.
  def second_step(anchor_id)
    @second_step[anchor_id] ||= begin
      first = SongNeighbor.where(song_id: anchor_id).pluck(:neighbor_id, :score).to_h
      best = {}
      neighbour_rows(first.keys).each do |from_id, id, artist_id, genre_id, title, recording, score, *dials|
        base = first[from_id] * score * SECOND_STEP * SEED_WEIGHT
        next if id == anchor_id || (best[id] && best[id]["base"] >= base)
        best[id] = to_row(id, artist_id, genre_id, title, recording, dials, base)
      end
      best
    end
  end

  def candidates(sources, anchor, context)
    best = second_step(anchor.id).transform_values(&:dup)
    neighbour_rows(sources.keys).each do |from_id, id, artist_id, genre_id, title, recording, score, *dials|
      if score >= DUPLICATE_SCORE   # another copy of a source song
        best.delete(id)
        @exclude << id.to_s
        next
      end
      base = score * sources[from_id]
      next if best[id] && best[id]["base"] >= base
      best[id] = to_row(id, artist_id, genre_id, title, recording, dials, base)
    end

    rows = best.values.reject { |row| rejected?(row, context) }
    credited = credit_blocked(rows.map { |r| r["id"] })
    rows.reject! { |row| credited.include?(row["id"]) }
    rows.each { |row| score!(row, context) }
    apply_taste!(rows)
    rows
  end

  def rejected?(row, context)
    id = row["id"].to_s
    return true if @exclude.include?(id)
    return true if @allowed && !@allowed.include?(id)
    return true if @genres && !@genres.include?(row["genre_id"])
    return true if row["artist_id"] && (context[:blocked_artists].include?(row["artist_id"]) ||
                                        @taste.removed_artist_ids.include?(row["artist_id"]))
    return true if !context[:allow_speech] && row["speech"].to_f >= SPEECH_CUTOFF
    return true if row["title_key"] && @recent_titles.include?(row["title_key"])
    return true if row["recording"] && @recent_recordings.include?(row["recording"])
    false
  end

  def credit_blocked(ids)
    return Set.new if @taste.removed_artist_ids.empty?
    unknown = ids.reject { |id| @credit_checked.key?(id) }
    if unknown.any?
      hit = @taste.credits_removed_artist(unknown)
      unknown.each { |id| @credit_checked[id] = hit.include?(id) }
    end
    Set.new(ids.select { |id| @credit_checked[id] })
  end

  def score!(row, context)
    notes = {}
    weight = row["base"]
    energy = row["energy"].to_f
    notes["flow"] = -FLOW_STRENGTH * (energy - context[:target]).abs
    jump = (energy - context[:dials]["energy"].to_f).abs - max_step
    notes["step"] = -STEP_STRENGTH * jump if jump.positive?
    lean = 0.0
    @steer.each do |dial, push|
      lean += STEER_STRENGTH * push * (row[dial].to_f - context[:anchor_dials][dial].to_f).clamp(-DIAL_SPAN, DIAL_SPAN)
    end
    @taste.learned_dials.except("energy").each do |dial, push|
      lean += LEARN_STRENGTH * push * (row[dial].to_f - context[:anchor_dials][dial].to_f).clamp(-DIAL_SPAN, DIAL_SPAN)
    end
    notes["lean"] = lean unless lean.zero?
    skips = @taste.skipped[row["id"]]
    notes["skipped"] = -SKIP_PENALTY * skips if skips.positive?
    notes["artist"] = -SOFT_ARTIST_PENALTY if row["artist_id"] && @taste.soft_artist_ids.include?(row["artist_id"])
    row["notes"] = notes
    row["weight"] = weight + notes.values.sum
  end

  # Pull the best candidates toward the station's taste: closeness to the taste vector, measured in
  # standard deviations among those candidates so it means the same whatever the neighbourhood.
  def apply_taste!(rows)
    vector = @taste.vector
    strength = TASTE_STRENGTH * @taste.confidence
    return if vector.nil? || strength.zero? || rows.size < 3
    top = rows.max_by(TASTE_POOL) { |r| r["weight"] }
    missing = top.map { |r| r["id"] }.reject { |id| @embeddings.key?(id) }
    SongEmbedding.where(song_id: missing).pluck(:song_id, :embedding).each { |id, e| @embeddings[id] = e } if missing.any?
    scored = top.filter_map do |row|
      e = @embeddings[row["id"]]
      next if e.blank?
      dot = 0.0
      e.each_with_index { |x, i| dot += x * vector[i] }
      [ row, dot ]
    end
    return if scored.size < 3
    mean = scored.sum { |_, d| d } / scored.size
    sd = Math.sqrt(scored.sum { |_, d| (d - mean)**2 } / scored.size)
    return if sd < 1e-6
    scored.each do |row, dot|
      bonus = strength * ((dot - mean) / sd).clamp(-2.0, 2.0)
      row["notes"]["taste"] = bonus
      row["weight"] += bonus
    end
  end

  # Weighted random choice among the best few, so the same seed does not always give the same stream.
  def pick(cands)
    return nil if cands.empty?

    pool = cands.max_by(POOL) { |c| c["weight"] }
    floor = pool.last["weight"]
    weights = pool.map { |c| (c["weight"] - floor) + 0.05 }
    target = @random.rand * weights.sum
    pool.each_with_index do |c, i|
      target -= weights[i]
      return c if target <= 0
    end
    pool.first
  end
end
