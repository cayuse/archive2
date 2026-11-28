# Keeps one playing copy of each recording, without deleting anything. See
# docs/reference/LIBRARY_QUALITY.md.
#
# merge(song): a song that has just been measured is compared with the live copies of the same
# recording (Fingerprint.matches). Whichever is better by CopyRanking stays live; the other is hidden
# onto it (hide!). A new copy takes over only when it is better at a level worth a swap (intact over
# broken, lossless over lossy, hi-res over CD, a clearly higher cutoff or bitrate tier); otherwise the
# copy already there stays, so re-releases do not flip-flop.
#
# hide!(song, onto:) moves what pointed at the hidden copy to the one that plays, in one transaction,
# and logs each move in a SongMerge:
#   playlists       the slot moves to the survivor; if the survivor is already on that playlist the
#                   survivor keeps the earlier of the two positions and the copy's row goes (logged)
#   play queues     queued plays of the copy play the survivor
#   station votes   move with the song, except a thumbs-down on a copy hidden as broken: that vote was
#                   most likely about the damage, not the song (CARRY_DOWN_FROM_BROKEN)
#   hidden copies   copies that pointed at this one now point at the survivor (no chains)
# Play history, sound analysis and neighbours stay with the file they describe.
#
# restore!(merge) puts back every row the merge moved and makes the copy live again.
class SongMerger
  CARRY_DOWN_FROM_BROKEN = false

  Result = Struct.new(:outcome, :canonical, :others, :why, keyword_init: true)
  # outcome: "new"        no other copy of this recording
  #          "better"     this copy plays now; +others+ were hidden onto it
  #          "not_better" hidden onto +canonical+, which is as good or better

  def initialize(source: "intake", log: Rails.logger)
    @source = source
    @log = log
  end

  def merge(song)
    m = song.measurement
    return Result.new(outcome: "new", others: []) unless m&.fingerprint.present?
    measure_namesakes(song)
    ids = Fingerprint.matches(m)[:same].map(&:first)
    # copies already hidden lead to the one that plays; only live, measured copies are compared
    live = Song.where(id: ids).includes(:measurement, :album).map(&:playable_song).uniq
               .reject { |s| s.id == song.id || s.hidden? || s.measurement.nil? }
    return Result.new(outcome: "new", others: []) if live.empty?

    best = live.max_by { |s| CopyRanking.full_strength(s) }
    if CopyRanking.better?(m, best.measurement)
      why = CopyRanking.reasons(m, best.measurement).join("; ").presence || "better"
      live.each { |old| hide!(old, onto: song, reason: "superseded", why: why) }
      Result.new(outcome: "better", canonical: song, others: live, why: why)
    else
      why = CopyRanking.reasons(best.measurement, m).join("; ").presence || "same quality"
      hide!(song, onto: best, reason: "duplicate", why: why)
      Result.new(outcome: "not_better", canonical: best, others: [], why: why)
    end
  end

  def hide!(song, onto:, reason:, why: nil)
    raise ArgumentError, "a song cannot be hidden onto itself" if song.id == onto.id
    raise ArgumentError, "#{onto.id} is itself hidden" if onto.reload.hidden?
    moves = []
    Song.transaction do
      song.lock!
      # copies that pointed here point at the survivor
      ids = Song.where(canonical_song_id: song.id).pluck(:id)
      if ids.any?
        Song.where(id: ids).update_all(canonical_song_id: onto.id, updated_at: Time.current)
        moves << { "t" => "songs", "ids" => ids, "from" => song.id, "to" => onto.id }
      end
      moves.concat(move_playlist_slots(song, onto))
      queued = AjbQueueItem.where(song_id: song.id).pluck(:id)
      if queued.any?
        AjbQueueItem.where(id: queued).update_all(song_id: onto.id, updated_at: Time.current)
        moves << { "t" => "ajb_queue_items", "ids" => queued, "from" => song.id, "to" => onto.id }
      end
      votes = StationFeedback.where(song_id: song.id)
      votes = votes.where.not(kind: "down") if !CARRY_DOWN_FROM_BROKEN && song.measurement&.verdict == "bad"
      vote_ids = votes.pluck(:id)
      if vote_ids.any?
        StationFeedback.where(id: vote_ids).update_all(song_id: onto.id, updated_at: Time.current)
        moves << { "t" => "station_feedbacks", "ids" => vote_ids, "from" => song.id, "to" => onto.id }
      end
      song.update_columns(canonical_song_id: onto.id, updated_at: Time.current)
      kind = reason == "superseded" ? "superseded" : "duplicate"
      SongIssue.create!(song: song, kind: kind, source: @source, related_song: onto, detail: { "why" => why }.compact)
      # what made it worth replacing is settled: the song that plays now is the one to judge
      song.issues.open.quality.each { |i| i.resolve!("replaced_by" => onto.id) }
      SongMerge.create!(song: song, canonical_song: onto, reason: reason, source: @source, moves: moves)
    end
  end

  def restore!(merge)
    raise ArgumentError, "already restored" if merge.reverted_at
    Song.transaction do
      merge.moves.reverse_each { |mv| undo(mv) }
      merge.song.update_columns(canonical_song_id: nil, updated_at: Time.current)
      merge.song.issues.open.where(kind: %w[superseded duplicate], related_song_id: merge.canonical_song_id)
           .each { |i| i.resolve!("restored" => true) }
      merge.update!(reverted_at: Time.current)
    end
  end

  private

  NAMESAKES = 20

  # Songs of the same title that were never measured (added by a path that does not measure, or after
  # the audit) cannot be found by fingerprint. Measure them from their stored files first, so a copy the
  # library already has is never missed.
  def measure_namesakes(song)
    return if song.title.blank?
    Song.where("lower(songs.title) = lower(?)", song.title).where.not(id: song.id).where(canonical_song_id: nil)
        .where.missing(:measurement).joins(:audio_file_attachment).limit(NAMESAKES).each do |other|
      other.audio_file.blob.open { |file| AudioAudit.measure_song!(other, file.path) }
      SongIssue.record_quality!(other, other.measurement, source: @source)
    rescue StandardError => e
      @log.warn "[SongMerger] could not measure #{other.id} (#{other.title}): #{e.class}: #{e.message}"
    end
  end

  def move_playlist_slots(song, onto)
    moves = []
    PlaylistsSong.where(song_id: song.id).to_a.each do |row|
      survivor = PlaylistsSong.find_by(playlist_id: row.playlist_id, song_id: onto.id)
      if survivor
        if row.position && (survivor.position.nil? || row.position < survivor.position)
          moves << { "t" => "playlists_songs.position", "playlist_id" => row.playlist_id, "song_id" => onto.id,
                     "from" => survivor.position, "to" => row.position }
          PlaylistsSong.where(playlist_id: row.playlist_id, song_id: onto.id).update_all(position: row.position)
        end
        moves << { "t" => "playlists_songs.removed", "row" => row.attributes.slice("playlist_id", "song_id", "position", "created_at") }
        PlaylistsSong.where(playlist_id: row.playlist_id, song_id: song.id).delete_all
      else
        PlaylistsSong.where(playlist_id: row.playlist_id, song_id: song.id).update_all(song_id: onto.id, updated_at: Time.current)
        moves << { "t" => "playlists_songs", "playlist_id" => row.playlist_id, "from" => song.id, "to" => onto.id }
      end
    end
    moves
  end

  def undo(mv)
    case mv["t"]
    when "songs"
      Song.where(id: mv["ids"], canonical_song_id: mv["to"]).update_all(canonical_song_id: mv["from"], updated_at: Time.current)
    when "ajb_queue_items"
      AjbQueueItem.where(id: mv["ids"], song_id: mv["to"]).update_all(song_id: mv["from"], updated_at: Time.current)
    when "station_feedbacks"
      StationFeedback.where(id: mv["ids"], song_id: mv["to"]).update_all(song_id: mv["from"], updated_at: Time.current)
    when "playlists_songs"
      unless PlaylistsSong.exists?(playlist_id: mv["playlist_id"], song_id: mv["from"])
        PlaylistsSong.where(playlist_id: mv["playlist_id"], song_id: mv["to"]).update_all(song_id: mv["from"], updated_at: Time.current)
      end
    when "playlists_songs.position"
      PlaylistsSong.where(playlist_id: mv["playlist_id"], song_id: mv["song_id"]).update_all(position: mv["from"])
    when "playlists_songs.removed"
      row = mv["row"]
      unless PlaylistsSong.exists?(playlist_id: row["playlist_id"], song_id: row["song_id"]) || !Playlist.exists?(row["playlist_id"])
        PlaylistsSong.insert_all([ row.merge("updated_at" => Time.current) ])
      end
    else
      @log.warn "[SongMerger] unknown move #{mv['t']}"
    end
  end
end
