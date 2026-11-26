# The sound-analysis API: how a machine with a GPU fills in what stations need (embeddings, dials,
# sound-alike lists) for songs the Drop Box has added. GET /api/v1/analysis describes every endpoint
# (AnalysisApiGuide); a client is meant to work from that description alone.
#
# It is opened by a ServiceKey of scope "analysis", never by a person's login, and deliberately
# shares nothing with the rest of the API: no session, no user, and writes only through
# AnalysisWriter, which touches four tables.
class Api::V1::AnalysisController < ActionController::API
  before_action :authenticate_key!
  after_action :note_use
  rescue_from(ActiveRecord::RecordNotFound) { render json: { error: "not found" }, status: :not_found }
  rescue_from(AnalysisWriter::Invalid) { |e| render json: { error: "nothing was written", problems: e.problems.first(100) }, status: :unprocessable_content }
  BadRequest = Class.new(StandardError)
  rescue_from(BadRequest) { |e| render json: { error: e.message }, status: :unprocessable_content }

  MAX_BODY = 20.megabytes

  def guide
    render json: AnalysisApiGuide.build(request.base_url)
  end

  def status
    model, dimensions = AnalysisWriter.library_model
    render json: { server_time: Time.current.utc.iso8601, songs: Song.count, songs_analysed: SongEmbedding.count,
                   songs_awaiting_analysis: Song.awaiting_analysis.count, analysis_model: model, embedding_dimensions: dimensions,
                   last_analysis_written_at: SongAudioFeature.maximum(:updated_at)&.utc&.iso8601,
                   newest_song_added_at: Song.maximum(:created_at)&.utc&.iso8601 }
  end

  def pending
    songs = Song.awaiting_analysis.order(:created_at, :id).limit(limit(100, 500))
    songs = songs.where("(songs.created_at, songs.id) > (?, ?)", *cursor_time_id) if params[:after].present?
    rows = songs.includes(:artist, :album, :genre, audio_file_attachment: :blob).to_a
    render json: { songs: rows.map { |s| song_json(s).merge(audio_url: "#{request.base_url}/api/v1/analysis/songs/#{s.id}/audio") },
                   next_after: rows.size == limit(100, 500) ? "#{rows.last.created_at.utc.iso8601(6)}|#{rows.last.id}" : nil,
                   server_time: Time.current.utc.iso8601 }
  end

  def songs
    scope = paged(Song.all, 500, 2000).includes(:artist, :album, :genre, audio_file_attachment: :blob)
    rows = scope.to_a
    analysed = SongEmbedding.where(song_id: rows.map(&:id)).pluck(:song_id).to_set
    out = page(rows, 500, 2000) { |s| song_json(s).merge(analysed: analysed.include?(s.id)) }
    render json: { songs: out[:rows], next_after: out[:next_after], server_time: out[:server_time] }
  end

  def audio
    song = Song.find(params[:id])
    return render json: { error: "this song has no audio file" }, status: :not_found unless song.audio_file.attached?
    blob = song.audio_file.blob
    return render json: { error: "this song's audio file is missing from storage" }, status: :not_found unless blob.service.exist?(blob.key)
    if blob.service.respond_to?(:path_for)
      send_file blob.service.path_for(blob.key), type: blob.content_type || "application/octet-stream", filename: blob.filename.to_s, disposition: "attachment"
    else
      send_data blob.download, type: blob.content_type || "application/octet-stream", filename: blob.filename.to_s, disposition: "attachment"
    end
  end

  def features
    rows = paged(SongAudioFeature.all, 1000, 5000, id_column: :song_id).to_a
    fields = SongAudioFeature::DIALS + AnalysisWriter::SIGNALS.keys
    out = page(rows, 1000, 5000) { |f| { song_id: f.song_id, analysis_model: f.analysis_model, analyzed_at: f.analyzed_at&.utc&.iso8601 }.merge(f.attributes.slice(*fields)) }
    render json: { features: out[:rows], next_after: out[:next_after], server_time: out[:server_time] }
  end

  def embeddings
    rows = paged(SongEmbedding.all, 500, 2000, id_column: :song_id).to_a
    out = page(rows, 500, 2000) do |e|
      { song_id: e.song_id, analysis_model: e.analysis_model, dimensions: e.dimensions, embedding_b64: Base64.strict_encode64(e.embedding.pack("e*")) }
    end
    render json: { embeddings: out[:rows], next_after: out[:next_after], server_time: out[:server_time] }
  end

  def neighbors
    ids = id_list or raise BadRequest, "ids is required: up to 200 song ids, comma-separated"
    lists = SongNeighbor.where(song_id: ids).order(:song_id, :rank).pluck(:song_id, :neighbor_id, :score).group_by(&:first)
    render json: { lists: ids.map { |id| { song_id: id, neighbors: (lists[id] || []).map { |_, n, score| { id: n, score: score } } } } }
  end

  def genres
    counts = Song.group(:genre_id).count
    render json: { genres: Genre.order(:name).map { |g| { id: g.id, name: g.name, songs: counts[g.id].to_i } } }
  end

  def genre_affinities
    render json: { affinities: GenreAffinity.order(:genre_id, score: :desc).pluck(:genre_id, :related_genre_id, :score)
                                            .map { |g, r, s| { genre_id: g, related_genre_id: r, score: s } } }
  end

  def write_results
    wrote AnalysisWriter.new.write_results(model: body["model"].to_s, songs: body["songs"], replace: body["replace"] == true)
  end

  def write_neighbors
    wrote AnalysisWriter.new.write_neighbors(lists: body["lists"])
  end

  def write_genre_affinities
    wrote AnalysisWriter.new.write_genre_affinities(affinities: body["affinities"], allow_shrink: body["allow_shrink"] == true)
  end

  private

  def authenticate_key!
    token = request.headers["Authorization"].to_s[/\ABearer\s+(\S+)\z/, 1]
    @key = ServiceKey.authenticate(token, scope: "analysis")
    render json: { error: "a valid analysis key is required: Authorization: Bearer <key>" }, status: :unauthorized unless @key
  end

  def note_use
    @key&.used!(ip: request.remote_ip, wrote: @wrote.to_i)
  end

  def wrote(result)
    @wrote = 1
    Rails.logger.info "[analysis] key=#{@key.name} #{action_name} #{result.to_json}"
    render json: { written: result }
  end

  # The JSON body of a write, as plain hashes. Not the usual params: nothing here is mass-assigned,
  # every value is checked by AnalysisWriter.
  def body
    @body ||= begin
      raise BadRequest, "the request body is larger than #{MAX_BODY / 1.megabyte} MB; send smaller batches" if request.content_length.to_i > MAX_BODY
      parsed = JSON.parse(request.raw_post)
      parsed.is_a?(Hash) ? parsed : raise(BadRequest, "the body must be a JSON object")
    rescue JSON::ParserError => e
      raise BadRequest, "the body is not valid JSON (#{e.message.first(120)})"
    end
  end

  def limit(default, max)
    value = params[:limit].to_i
    value.positive? ? [ value, max ].min : default
  end

  def id_list
    return nil if params[:ids].blank?
    ids = params[:ids].to_s.split(",").map { |i| i.strip.downcase }
    raise BadRequest, "ids: up to 200 song ids, comma-separated" if ids.size > 200 || !ids.all? { |i| i.match?(AnalysisWriter::UUID) }
    ids
  end

  def since
    return nil if params[:since].blank?
    Time.iso8601(params[:since].to_s)
  rescue ArgumentError
    raise BadRequest, "since must be an ISO 8601 time, like 2026-11-26T15:00:00Z"
  end

  def cursor_time_id
    time, id = params[:after].to_s.split("|", 2)
    [ Time.iso8601(time), id.to_s ]
  rescue ArgumentError
    raise BadRequest, "after must be the next_after value of the previous page"
  end

  # Rows ordered by id, after the cursor, optionally only those changed since a time or with given ids.
  def paged(scope, default, max, id_column: :id)
    table = scope.klass.arel_table
    scope = scope.order(table[id_column]).limit(limit(default, max))
    if params[:after].present?
      raise BadRequest, "after must be the next_after value of the previous page" unless params[:after].to_s.match?(AnalysisWriter::UUID)
      scope = scope.where(table[id_column].gt(params[:after].to_s))
    end
    scope = scope.where(table[:updated_at].gteq(since)) if since
    scope = scope.where(id_column => id_list) if id_list
    scope
  end

  def page(rows, default, max)
    last = rows.last
    { rows: rows.map { |r| yield r }, next_after: rows.size == limit(default, max) ? (last.respond_to?(:song_id) ? last.song_id : last.id) : nil,
      server_time: Time.current.utc.iso8601 }
  end

  def song_json(song)
    { id: song.id, title: song.title, artist: song.artist && { id: song.artist_id, name: song.artist.name },
      album: song.album && { id: song.album_id, title: song.album.title }, genre: song.genre && { id: song.genre_id, name: song.genre.name },
      duration: song.duration, file_format: song.file_format, byte_size: song.audio_file.attached? ? song.audio_file.byte_size : nil,
      musicbrainz_recording_id: song.musicbrainz_recording_id, created_at: song.created_at.utc.iso8601, updated_at: song.updated_at.utc.iso8601 }
  end
end
