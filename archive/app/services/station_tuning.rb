# Everything that shapes a station, gathered for the tuning page: its seeds, what the listener
# liked, rejected and shelved, the artists taken off it, and what it has learned.
class StationTuning
  LIMIT = 200

  def initialize(jukebox, user)
    @jukebox, @user = jukebox, user
    @station = jukebox.station
    @taste = StationTaste.new(user: user, station: @station, learn: jukebox.radio_learn?)
  end

  def as_json(*)
    rows = StationFeedback.log_for(user: @user, station: @station).where(kind: %w[up down clear tired never])
                          .order(created_at: :desc).pluck(:song_id, :kind, :created_at, :expires_at)
    thumbs = StationFeedback.thumbs(rows.map { |song_id, kind, at, _| [ song_id, kind, at ] })
    feedback = thumbs.map { |song_id, (kind, at)| [ song_id, kind, at, nil ] }.sort_by { |r| r[2] }.reverse +
               rows.select { |_, kind, _, _| kind.in?(%w[tired never]) }
    played = @jukebox.ajb_played_songs.order(played_at: :desc).limit(30).pluck(:song_id, :played_at, :source)
    artist_ids = @taste.removed_artist_ids.to_a + @jukebox.radio_kept_artist_ids
    songs = Song.includes(:artist, :album).where(id: @jukebox.radio_seed_ids + feedback.map(&:first) + played.map(&:first)).index_by(&:id)
    artists = Artist.where(id: artist_ids).index_by(&:id)
    standings = StationFeedback.standings(user: @user, song_ids: played.map(&:first), station: @station)
    by_kind = feedback.group_by { |_, kind, _, _| kind }
    list = lambda do |kind|
      (by_kind[kind] || []).first(LIMIT).filter_map do |song_id, _, at, expires|
        songs[song_id] && song_json(songs[song_id]).merge(at: at&.iso8601, expires_at: expires&.iso8601)
      end
    end

    {
      seeds: @jukebox.radio_seed_ids.filter_map { |id| songs[id] && song_json(songs[id]) },
      liked: list.call("up"),
      disliked: list.call("down"),
      tired: list.call("tired"),
      never: list.call("never"),
      removed_artists: @taste.removed_artist_ids.filter_map do |id|
        artists[id] && { id: id, name: artists[id].name, downs: @taste.artist_votes.dig(id, :down) }
      end,
      kept_artists: @jukebox.radio_kept_artist_ids.filter_map { |id| artists[id] && { id: id, name: artists[id].name } },
      learned_dials: @taste.learned_dials,
      taste_confidence: @taste.confidence.round(2),
      skipped: @taste.skipped.size,
      recent: played.filter_map do |song_id, at, source|
        songs[song_id] && song_json(songs[song_id]).merge(played_at: at&.iso8601, source: source, standing: standings[song_id])
      end
    }
  end

  private

  def song_json(song)
    { id: song.id, title: song.title, artist: song.artist&.name, album: song.album&.title, duration: song.duration }
  end
end
