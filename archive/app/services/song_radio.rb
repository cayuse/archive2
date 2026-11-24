# Builds an endless-style stream from a seed song: "play things that sound like this".
#
# It walks the precomputed sounds-like links (song_neighbors). Each step picks from the neighbours
# of the seed (keeps the theme) and of the song just picked (lets the stream drift).
#
# What it takes into account:
#   * sound similarity to the seed and to the song just picked
#   * no repeats; a gap before the same artist comes round again
#   * no spoken word unless the seed is spoken word
#   * steer:      dials to push, each -1.0..1.0, e.g. { energy: 0.5, acousticness: -1 }
#   * genre_mode: "any" (default), "adjacent" (seed's genre plus genres that sound like it in this
#                 library, see GenreAffinity) or "strict" (seed's genre only)
#   * user:       their thumbs. Thumbs-down songs never play; songs that sound like thumbs-ups are
#                 boosted, songs that sound like thumbs-downs (and artists repeatedly thumbed down)
#                 are pushed back
#   * allowed_ids: only these songs may be picked (e.g. a jukebox's assigned playlists)
#
#   SongRadio.new(seed: song).next_songs(20)
#   SongRadio.new(seed: song, user: current_user, genre_mode: "adjacent", steer: { energy: -1 }).next_songs(10)
class SongRadio
  DIALS = SongAudioFeature::DIALS
  GENRE_MODES = %w[any adjacent strict].freeze
  SPEECH_CUTOFF = 0.96      # top 4% of the "speech" dial is audiobooks and talking
  ARTIST_GAP = 3            # songs before an artist may come round again
  POOL = 8                  # choose at random among this many best candidates
  SEED_WEIGHT = 1.0
  DRIFT_WEIGHT = 0.85
  STEER_STRENGTH = 0.6
  LIKE_BOOST = 0.08         # candidate sounds like songs the user thumbed up
  DISLIKE_PENALTY = 0.12    # candidate sounds like songs the user thumbed down
  ARTIST_PENALTY = 0.15     # artist the user has thumbed down at least twice more than up

  def initialize(seed:, exclude_ids: [], steer: {}, allowed_ids: nil, genre_mode: "any", user: nil, random: Random.new)
    @seed = seed
    @exclude = Set.new(exclude_ids.map(&:to_s)) << seed.id.to_s
    @allowed = allowed_ids && Set.new(allowed_ids.map(&:to_s))
    @steer = steer.to_h.transform_keys(&:to_s).slice(*DIALS)
                  .transform_values { |v| v.to_f.clamp(-1.0, 1.0) }.reject { |_, v| v.zero? }
    @genres = allowed_genres(GENRE_MODES.include?(genre_mode.to_s) ? genre_mode.to_s : "any")
    @random = random
    load_taste(user)
  end

  # Returns up to +count+ songs, in play order. Empty if the seed has not been analysed.
  def next_songs(count = 20)
    seed_dials = dials_for(@seed.id)
    return [] if seed_dials.nil?

    allow_speech = seed_dials["speech"].to_f >= SPEECH_CUTOFF
    current_id = @seed.id
    current_dials = seed_dials
    recent_artists = [ @seed.artist_id ].compact
    picked = []

    count.times do
      blocked = recent_artists.last(ARTIST_GAP)
      cands = candidates([ @seed.id, current_id ].uniq, current_dials, allow_speech, blocked)
      # ran dry (tight genre or playlist limits): widen to everything picked so far
      cands = candidates([ @seed.id ] + picked.last(12), current_dials, allow_speech, blocked) if cands.empty? && picked.any?
      choice = pick(cands)
      break unless choice

      picked << choice["id"]
      @exclude << choice["id"].to_s
      recent_artists << choice["artist_id"] if choice["artist_id"]
      current_id = choice["id"]
      current_dials = choice.slice(*DIALS)
    end

    songs = Song.includes(:artist, :album, :genre, :audio_feature).where(id: picked).index_by(&:id)
    picked.filter_map { |id| songs[id] }
  end

  private

  def dials_for(song_id)
    SongAudioFeature.where(song_id: song_id).pick(*DIALS)&.then { |row| DIALS.zip(row).to_h }
  end

  # nil = any genre
  def allowed_genres(mode)
    return nil if mode == "any" || @seed.genre_id.nil?

    ids = [ @seed.genre_id ]
    # adjacent also lets in songs with no genre tag: they got here by sounding like the seed
    ids += GenreAffinity.where(genre_id: @seed.genre_id).pluck(:related_genre_id) + [ nil ] if mode == "adjacent"
    Set.new(ids)
  end

  def load_taste(user)
    @near_liked = {}
    @near_disliked = {}
    @bad_artists = Set.new
    return unless user

    ratings = SongRating.where(user_id: user.id).pluck(:song_id, :value)
    up = ratings.select { |_, v| v.positive? }.map(&:first)
    down = ratings.select { |_, v| v.negative? }.map(&:first)
    down.each { |id| @exclude << id.to_s }
    @near_liked = SongNeighbor.where(song_id: up).group(:neighbor_id).count if up.any?
    @near_disliked = SongNeighbor.where(song_id: down).group(:neighbor_id).count if down.any?

    by_artist = Hash.new(0)
    Song.where(id: up + down).where.not(artist_id: nil).pluck(:id, :artist_id).each do |id, artist_id|
      by_artist[artist_id] += up.include?(id) ? 1 : -1
    end
    @bad_artists = Set.new(by_artist.select { |_, net| net <= -2 }.keys)
  end

  def candidates(from, current_dials, allow_speech, blocked_artists)
    rows = SongNeighbor.where(song_id: from)
                       .joins("JOIN songs ON songs.id = song_neighbors.neighbor_id")
                       .joins("JOIN song_audio_features f ON f.song_id = song_neighbors.neighbor_id")
                       .pluck(Arel.sql("song_neighbors.song_id"), Arel.sql("songs.id"), Arel.sql("songs.artist_id"),
                              Arel.sql("songs.genre_id"), Arel.sql("song_neighbors.score"),
                              *DIALS.map { |d| Arel.sql("f.#{d}") })

    best = {}
    rows.each do |from_id, id, artist_id, genre_id, score, *dials|
      next if @exclude.include?(id.to_s)
      next if @allowed && !@allowed.include?(id.to_s)
      next if @genres && !@genres.include?(genre_id)
      next if artist_id && blocked_artists.include?(artist_id)

      row = DIALS.zip(dials).to_h
      next if !allow_speech && row["speech"].to_f >= SPEECH_CUTOFF

      weight = score * (from_id == @seed.id ? SEED_WEIGHT : DRIFT_WEIGHT)
      @steer.each do |dial, push|
        weight += STEER_STRENGTH * push * (row[dial].to_f - current_dials[dial].to_f)
      end
      weight += LIKE_BOOST * [ @near_liked[id].to_i, 3 ].min / 3.0
      weight -= DISLIKE_PENALTY * [ @near_disliked[id].to_i, 3 ].min / 3.0
      weight -= ARTIST_PENALTY if artist_id && @bad_artists.include?(artist_id)
      next if best[id] && best[id]["weight"] >= weight

      best[id] = row.merge("id" => id, "artist_id" => artist_id, "weight" => weight)
    end
    best.values
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
