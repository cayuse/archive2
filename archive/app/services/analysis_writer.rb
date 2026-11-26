# The only way the analysis API changes the database. It writes four tables and nothing else:
# song_audio_features, song_embeddings, song_neighbors and genre_affinities. Every request is
# checked in full before anything is written and then written in one transaction, so a request is
# either wholly applied or not at all. What is checked is spelled out to clients in AnalysisApiGuide.
class AnalysisWriter
  class Invalid < StandardError
    attr_reader :problems
    def initialize(problems)
      @problems = Array(problems)
      super(@problems.first(5).join("; "))
    end
  end

  MAX_SONGS = 200            # per results request
  MAX_LISTS = 500            # neighbour lists per request
  MAX_NEIGHBORS = 50         # per song
  MAX_AFFINITIES = 50_000
  DIALS = SongAudioFeature::DIALS
  SIGNALS = { "analyzed_seconds" => 0.1..100_000, "loudness_db" => -150..30, "peak_db" => -150..30, "tempo_bpm" => 20..400,
              "brightness_hz" => 0..30_000, "onset_strength" => 0..1000 }.freeze
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # The model and vector size the library's sound data was made with. Results from another model
  # cannot be compared with it, so they are refused. nil while the library has no analysis at all.
  def self.library_model = SongEmbedding.group(:analysis_model, :dimensions).order(Arel.sql("count(*) desc")).limit(1).count.keys.first

  # --- features and embeddings for songs ---

  def write_results(model:, songs:, replace: false)
    problems = []
    songs = Array(songs)
    problems << "send between 1 and #{MAX_SONGS} songs per request (got #{songs.size})" unless (1..MAX_SONGS).cover?(songs.size)
    library_model, dimensions = self.class.library_model
    problems << "model must be #{library_model.inspect}, the model the library was analysed with" if library_model && model != library_model
    problems << "model is required" if model.blank?
    raise Invalid, problems if problems.any?

    ids = songs.map { |s| s["song_id"].to_s.downcase }
    problems << "a song_id appears more than once" if ids.uniq.size != ids.size
    known = Song.joins(:audio_file_attachment).where(id: ids.grep(UUID)).pluck(:id).to_set
    done = SongAudioFeature.where(song_id: known.to_a).pluck(:song_id).to_set | SongEmbedding.where(song_id: known.to_a).pluck(:song_id).to_set
    rows = songs.each_with_index.map do |entry, i|
      id = ids[i]
      at = "songs[#{i}] (#{id})"
      problems << "#{at}: no such song with an audio file" unless known.include?(id)
      problems << "#{at}: already analysed; send \"replace\": true to overwrite it" if done.include?(id) && !replace
      features = entry["features"].respond_to?(:to_h) ? entry["features"].to_h : {}
      dials = DIALS.to_h { |d| [ d, number(features[d], 0..1, "#{at}: features.#{d}", problems, required: true) ] }
      signals = SIGNALS.to_h { |name, range| [ name, number(features[name], range, "#{at}: features.#{name}", problems) ] }
      embedding = embedding_of(entry, dimensions, at, problems)
      { id: id, features: dials.merge(signals), embedding: embedding }
    end
    raise Invalid, problems if problems.any?

    now = Time.current
    ActiveRecord::Base.transaction do
      SongAudioFeature.upsert_all(rows.map { |r| r[:features].merge(song_id: r[:id], analysis_model: model, analyzed_at: now, created_at: now, updated_at: now) },
                                  unique_by: :song_id, update_only: DIALS + SIGNALS.keys + %w[analysis_model analyzed_at])
      SongEmbedding.upsert_all(rows.map { |r| { song_id: r[:id], analysis_model: model, dimensions: r[:embedding].size, embedding: r[:embedding], created_at: now, updated_at: now } },
                               unique_by: :song_id, update_only: %w[analysis_model dimensions embedding])
    end
    { songs: rows.size }
  end

  # --- sound-alike lists: each list given replaces that song's list ---

  def write_neighbors(lists:)
    problems = []
    lists = Array(lists)
    problems << "send between 1 and #{MAX_LISTS} lists per request (got #{lists.size})" unless (1..MAX_LISTS).cover?(lists.size)
    raise Invalid, problems if problems.any?

    owners = lists.map { |l| l["song_id"].to_s.downcase }
    problems << "a song_id appears more than once" if owners.uniq.size != owners.size
    every = (owners + lists.flat_map { |l| Array(l["neighbors"]).map { |n| n["id"].to_s.downcase } }).grep(UUID).uniq
    analysed = SongEmbedding.where(song_id: every).pluck(:song_id).to_set
    rows = []
    lists.each_with_index do |list, i|
      owner = owners[i]
      at = "lists[#{i}] (#{owner})"
      neighbors = Array(list["neighbors"])
      problems << "#{at}: not an analysed song" unless analysed.include?(owner)
      problems << "#{at}: give between 1 and #{MAX_NEIGHBORS} neighbors (got #{neighbors.size})" unless (1..MAX_NEIGHBORS).cover?(neighbors.size)
      ids = neighbors.map { |n| n["id"].to_s.downcase }
      problems << "#{at}: a neighbor appears more than once" if ids.uniq.size != ids.size
      problems << "#{at}: a song cannot be its own neighbor" if ids.include?(owner)
      missing = ids.reject { |id| analysed.include?(id) }
      problems << "#{at}: #{missing.size} neighbors are not analysed songs (first: #{missing.first})" if missing.any?
      scores = neighbors.each_with_index.map { |n, j| number(n["score"], -1..1.0001, "#{at}: neighbors[#{j}].score", problems, required: true) }
      problems << "#{at}: neighbors must be ordered best first (scores never rising)" if scores.compact.each_cons(2).any? { |a, b| b > a + 1e-9 }
      ids.each_with_index { |id, rank| rows << { song_id: owner, neighbor_id: id, rank: rank, score: scores[rank] } }
    end
    raise Invalid, problems if problems.any?

    now = Time.current
    ActiveRecord::Base.transaction do
      SongNeighbor.where(song_id: owners).delete_all
      rows.each_slice(5000) { |slice| SongNeighbor.insert_all(slice.map { |r| r.merge(created_at: now, updated_at: now) }) }
    end
    { lists: lists.size, links: rows.size }
  end

  # --- which genres sound alike: the whole table is replaced ---

  def write_genre_affinities(affinities:, allow_shrink: false)
    problems = []
    affinities = Array(affinities)
    problems << "send between 1 and #{MAX_AFFINITIES} affinities (got #{affinities.size})" unless (1..MAX_AFFINITIES).cover?(affinities.size)
    current = GenreAffinity.count
    if affinities.size < current / 2 && !allow_shrink
      problems << "this would shrink the table from #{current} rows to #{affinities.size}; this call replaces the WHOLE table. Send everything, or \"allow_shrink\": true if that is intended"
    end
    raise Invalid, problems if problems.any?

    genres = Genre.pluck(:id).to_set
    seen = Set.new
    rows = affinities.each_with_index.map do |a, i|
      pair = [ a["genre_id"].to_s.downcase, a["related_genre_id"].to_s.downcase ]
      at = "affinities[#{i}]"
      problems << "#{at}: no such genre" unless pair.all? { |id| genres.include?(id) }
      problems << "#{at}: a genre cannot be related to itself" if pair.uniq.size == 1
      problems << "#{at}: this pair appears more than once" unless seen.add?(pair)
      { genre_id: pair[0], related_genre_id: pair[1], score: number(a["score"], 0..1_000_000, "#{at}: score", problems, required: true) }
    end
    raise Invalid, problems if problems.any?

    now = Time.current
    ActiveRecord::Base.transaction do
      GenreAffinity.delete_all
      rows.each_slice(5000) { |slice| GenreAffinity.insert_all(slice.map { |r| r.merge(created_at: now, updated_at: now) }) }
    end
    { affinities: rows.size, replaced: current }
  end

  private

  def number(value, range, label, problems, required: false)
    if value.nil? || value == ""
      problems << "#{label} is required" if required
      return nil
    end
    n = value.is_a?(Numeric) ? value.to_f : Float(value.to_s, exception: false)
    if n.nil? || !n.finite? || !range.cover?(n)
      problems << "#{label} must be a number from #{range.begin} to #{range.end.is_a?(Float) ? range.end.floor : range.end} (got #{value.inspect.first(30)})"
      return nil
    end
    n
  end

  def embedding_of(entry, dimensions, at, problems)
    vector = if entry["embedding_b64"].present?
      Base64.strict_decode64(entry["embedding_b64"].to_s).unpack("e*")
    else
      Array(entry["embedding"]).map { |v| v.is_a?(Numeric) ? v.to_f : Float::NAN }
    end
    if vector.empty? then problems << "#{at}: embedding (an array of numbers) or embedding_b64 (little-endian float32, base64) is required"
    elsif dimensions && vector.size != dimensions then problems << "#{at}: embedding must have #{dimensions} numbers (got #{vector.size})"
    elsif vector.size > 4096 then problems << "#{at}: embedding is too long"
    elsif !vector.all?(&:finite?) then problems << "#{at}: embedding holds something that is not a finite number"
    elsif vector.all?(&:zero?) then problems << "#{at}: embedding is all zeros"
    end
    vector
  rescue ArgumentError
    problems << "#{at}: embedding_b64 is not valid base64"
    []
  end
end
