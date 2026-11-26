# What a station has learned from its listener's feedback (StationFeedback), in the form the radio
# needs: songs that must not play, artists taken off the station, a "taste" direction in sound
# space, and leanings on the mood dials.
#
#   taste = StationTaste.new(user: user, station: station)     # a Station, or nil for the user's own thumbs
#   taste.blocked_ids          # Set of song ids that must not be picked
#   taste.removed_artist_ids   # Set: thumbed down twice on this station with no thumbs up
#   taste.vector               # unit vector (Array<Float>) or nil when there is nothing to go on
#   taste.learned_dials        # { "aggression" => -0.4, ... } leanings worked out from the thumbs
#
# The vector is relevance feedback in the Rocchio style: the mean of what was liked minus a share
# of the mean of what was rejected. Early skips count as weak rejections, full plays as weak likes.
class StationTaste
  ARTIST_DOWNS = 2            # downs (with no ups) that take an artist off the station
  SKIPS_TO_BLOCK = 2          # early skips of one song that count as a thumbs down
  NEGATIVE_SHARE = 0.5        # how hard rejections push the taste vector away
  SKIP_WEIGHT = 0.4           # an early skip, relative to a thumbs down
  FINISHED_WEIGHT = 0.15      # a full play, relative to a thumbs up
  FULL_CONFIDENCE = 8.0       # this much weighted feedback = taste applied at full strength
  DIAL_MIN_VOTES = 3          # ups and downs needed before a dial leaning is trusted
  DIAL_MIN_GAP = 0.15         # and how far apart their averages must be (dials are 0..1)
  DIAL_MAX_LEAN = 0.6
  RECENT = 300                # only the newest events of each kind are used

  attr_reader :liked_ids, :disliked_ids, :blocked_ids, :skipped, :finished_ids,
              :removed_artist_ids, :soft_artist_ids, :artist_votes

  def initialize(user:, station: nil, learn: true)
    @user, @station, @learn = user, station, learn
    @liked_ids, @disliked_ids, @finished_ids = [], [], []
    @blocked_ids = Set.new
    @skipped = Hash.new(0)
    @removed_artist_ids, @soft_artist_ids = Set.new, Set.new
    @artist_votes = {}
    load_feedback if user
  end

  def any?
    @liked_ids.any? || @disliked_ids.any? || @skipped.any?
  end

  # 0..1: how much to trust the taste vector.
  def confidence
    weight = @liked_ids.size + 0.5 * @disliked_ids.size + SKIP_WEIGHT * 0.5 * @skipped.size +
             FINISHED_WEIGHT * @finished_ids.size
    [ weight / FULL_CONFIDENCE, 1.0 ].min
  end

  def vector
    return @vector if defined?(@vector)
    @vector = @learn ? build_vector : nil
  end

  def learned_dials
    return @learned_dials if defined?(@learned_dials)
    @learned_dials = @learn ? build_dials : {}
  end

  # Song ids among +song_ids+ that credit an artist who was taken off the station (catches
  # "Someone feat. Removed Artist", where the song's main artist is somebody else).
  def credits_removed_artist(song_ids)
    return Set.new if @removed_artist_ids.empty? || song_ids.empty?
    Set.new(SongArtistCredit.where(artist_id: @removed_artist_ids.to_a, song_id: song_ids).pluck(:song_id))
  end

  private

  def load_feedback
    # the station's log (for a copy: including what it inherited), newest first
    rows = StationFeedback.log_for(user: @user, station: @station)
                          .order(created_at: :desc).pluck(:song_id, :kind, :position, :created_at)
    by_kind = rows.group_by { |_, kind, _, _| kind }
    thumbs = StationFeedback.thumbs(rows.map { |song_id, kind, _, at| [ song_id, kind, at ] })
    newest_first = thumbs.sort_by { |_, (_, at)| at }.reverse
    @liked_ids = newest_first.select { |_, (kind, _)| kind == "up" }.map(&:first).first(RECENT)
    @disliked_ids = newest_first.select { |_, (kind, _)| kind == "down" }.map(&:first).first(RECENT)
    @finished_ids = (by_kind["finished"] || []).map(&:first).first(RECENT).uniq - @liked_ids - @disliked_ids
    (by_kind["skip"] || []).first(RECENT).each do |song_id, _, position, _|
      @skipped[song_id] += 1 if position.nil? || position < StationFeedback::EARLY_SKIP
    end
    @skipped.except!(*@liked_ids)
    @blocked_ids = Set.new(@disliked_ids)
    %w[tired never].each { |kind| (by_kind[kind] || []).each { |song_id, *| @blocked_ids << song_id } }
    @skipped.each { |song_id, n| @blocked_ids << song_id if n >= SKIPS_TO_BLOCK }
    load_artists
  end

  def load_artists
    voted = @liked_ids + @disliked_ids
    return if voted.empty?
    artist_of = Song.where(id: voted).where.not(artist_id: nil).pluck(:id, :artist_id).to_h
    votes = Hash.new { |h, k| h[k] = { up: 0, down: 0 } }
    @liked_ids.each { |id| votes[artist_of[id]][:up] += 1 if artist_of[id] }
    @disliked_ids.each { |id| votes[artist_of[id]][:down] += 1 if artist_of[id] }
    @artist_votes = votes
    kept = Set.new(@station&.kept_artist_ids || [])
    votes.each do |artist_id, v|
      if v[:down] >= ARTIST_DOWNS && v[:up].zero? && !kept.include?(artist_id.to_s)
        @removed_artist_ids << artist_id
      elsif v[:down] > v[:up]
        @soft_artist_ids << artist_id
      end
    end
  end

  def build_vector
    skipped_ids = @skipped.keys - @disliked_ids
    ids = (@liked_ids + @disliked_ids + @finished_ids + skipped_ids).uniq
    return nil if @liked_ids.empty? && @disliked_ids.empty? && skipped_ids.empty?
    emb = SongEmbedding.where(song_id: ids).pluck(:song_id, :embedding).to_h
    pos = weighted_mean(emb, @liked_ids.map { |id| [ id, 1.0 ] } + @finished_ids.map { |id| [ id, FINISHED_WEIGHT ] })
    neg = weighted_mean(emb, @disliked_ids.map { |id| [ id, 1.0 ] } + skipped_ids.map { |id| [ id, SKIP_WEIGHT ] })
    return nil unless pos || neg
    dims = (pos || neg).size
    v = Array.new(dims) { |i| (pos ? pos[i] : 0.0) - NEGATIVE_SHARE * (neg ? neg[i] : 0.0) }
    norm = Math.sqrt(v.sum { |x| x * x })
    norm < 1e-9 ? nil : v.map { |x| x / norm }
  end

  def weighted_mean(emb, pairs)
    sum, total = nil, 0.0
    pairs.each do |id, weight|
      e = emb[id]
      next if e.blank?
      sum ||= Array.new(e.size, 0.0)
      e.each_with_index { |x, i| sum[i] += weight * x }
      total += weight
    end
    sum && total.positive? ? sum.map { |x| x / total } : nil
  end

  def build_dials
    rejected = (@disliked_ids + @skipped.keys).uniq
    return {} if @liked_ids.size < DIAL_MIN_VOTES || rejected.size < DIAL_MIN_VOTES
    dials = SongAudioFeature::DIALS
    rows = SongAudioFeature.where(song_id: @liked_ids + rejected).pluck(:song_id, *dials).to_h { |id, *vals| [ id, vals ] }
    up = @liked_ids.filter_map { |id| rows[id] }
    down = rejected.filter_map { |id| rows[id] }
    return {} if up.size < DIAL_MIN_VOTES || down.size < DIAL_MIN_VOTES
    dials.each_with_index.filter_map do |dial, i|
      gap = mean(up.map { |r| r[i].to_f }) - mean(down.map { |r| r[i].to_f })
      next if gap.abs < DIAL_MIN_GAP
      [ dial, (gap * 1.5).clamp(-DIAL_MAX_LEAN, DIAL_MAX_LEAN).round(2) ]
    end.to_h
  end

  def mean(values)
    values.sum / values.size.to_f
  end
end
