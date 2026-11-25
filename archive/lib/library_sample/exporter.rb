require "json"
require "zlib"

module LibrarySample
  # Cuts a small, varied slice out of a full library database (the production clone) and writes it
  # as one gzipped JSON fixture that Seeder can load anywhere. Only reads from the database.
  #
  # The slice is three parts:
  #   spread  - songs spread over genre x tempo band x energy band, big genres damped (square root)
  #   albums  - a few complete albums, so album pages and track order have something real to show
  #   edges   - needs_review songs, songs the audio analysis never reached, many-artist credits
  # Sound-alike links are recomputed inside the slice from the embeddings, with the same rules as
  # library_tools/scripts/build_vectors.py (the production links almost all point outside it).
  class Exporter
    EDGE_CASES = 5
    ALBUM_SHARE = 0.2
    ALBUM_TRACKS = (6..16)
    NEIGHBORS = 30
    NEIGHBORS_PER_ARTIST = 4
    # Left out: big, and nothing in the app reads them.
    BLANKED_FILE_TAG_COLUMNS = { "raw_tags" => {}, "acoustid_fingerprint" => nil }.freeze

    def initialize(count:, path:, out: $stdout)
      @count = count
      @path = path
      @out = out
    end

    def call
      song_ids = (spread_ids + edge_ids + album_song_ids).uniq
      songs = in_order(Song.where(id: song_ids).as_json(except: %w[search_vector user_id]), song_ids)
      credits = SongArtistCredit.where(song_id: song_ids).order(:song_id, :position).as_json
      albums = Album.where(id: songs.filter_map { |s| s["album_id"] }.uniq).order(:id).as_json(except: %w[search_vector])
      artist_ids = (songs + albums).filter_map { |r| r["artist_id"] } + credits.map { |c| c["artist_id"] }
      genre_ids = songs.filter_map { |s| s["genre_id"] }.uniq
      embeddings = SongEmbedding.where(song_id: song_ids).order(:song_id).as_json
      embeddings.each { |e| e["embedding"] = e["embedding"].map { |x| x.round(4) } }

      payload = {
        "meta" => { "exported_at" => Time.now.utc.iso8601, "requested" => @count, "songs" => songs.size,
                    "note" => "0..1 dials are percentiles within the full source library, not within this slice" },
        "genres" => Genre.where(id: genre_ids).order(:name).as_json(except: %w[search_vector]),
        "artists" => Artist.where(id: artist_ids.uniq).order(:id).as_json(except: %w[search_vector]),
        "albums" => albums,
        "songs" => songs,
        "song_artist_credits" => credits,
        "song_file_tags" => SongFileTag.where(song_id: song_ids).order(:song_id).as_json.map { |t| t.merge(BLANKED_FILE_TAG_COLUMNS) },
        "song_audio_features" => SongAudioFeature.where(song_id: song_ids).order(:song_id).as_json,
        "song_embeddings" => embeddings,
        "song_neighbors" => neighbors(songs, embeddings),
        "genre_affinities" => GenreAffinity.where(genre_id: genre_ids, related_genre_id: genre_ids).order(:genre_id, :related_genre_id).as_json
      }
      FileUtils.mkdir_p(File.dirname(@path))
      Zlib::GzipWriter.open(@path) { |gz| gz.write(JSON.generate(payload)) }
      @out.puts payload.except("meta").map { |name, rows| "#{name}=#{rows.size}" }.join(" ")
      @out.puts "wrote #{@path} (#{File.size(@path) / 1024} KB)"
    end

    private

    def ids(sql, *binds)
      ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql([ sql, *binds ]))
    end

    def in_order(rows, song_ids)
      position = song_ids.each_with_index.to_h
      rows.sort_by { |r| position.fetch(r["id"]) }
    end

    # md5(id) is the tiebreak everywhere, so the same database always gives the same slice.
    # Ordered so that any prefix is itself spread: Seeder's LIMIT relies on that.
    def spread_ids
      ids(<<~SQL, (@count * (1 - ALBUM_SHARE)).round)
        with base as (
          select s.id, s.genre_id, md5(s.id::text) as h,
                 width_bucket(f.tempo_bpm, 70, 190, 6) as tempo_band,
                 least(floor(f.energy * 3), 2) as energy_band
          from songs s
          join song_audio_features f on f.song_id = s.id
          join song_embeddings e on e.song_id = s.id
          where s.processing_status = 'completed'
        ),
        weight as (select genre_id, sqrt(count(*)) as weight from base group by genre_id),
        celled as (
          select base.*, row_number() over (partition by genre_id, tempo_band, energy_band order by h) as cell_rank
          from base
        ),
        ranked as (
          select celled.*, row_number() over (partition by genre_id order by cell_rank, h) as genre_rank
          from celled
        )
        select r.id from ranked r
        join weight w on w.genre_id is not distinct from r.genre_id
        order by r.genre_rank / w.weight, r.h
        limit ?
      SQL
    end

    def edge_ids
      needs_review = ids("select id from songs where processing_status = 'needs_review' order by md5(id::text) limit ?", EDGE_CASES)
      unanalysed = ids(<<~SQL, EDGE_CASES)
        select s.id from songs s left join song_audio_features f on f.song_id = s.id
        where f.id is null order by md5(s.id::text) limit ?
      SQL
      many_credits = ids(<<~SQL, EDGE_CASES)
        select c.song_id from song_artist_credits c join song_embeddings e on e.song_id = c.song_id
        group by c.song_id having count(*) >= 3 order by md5(c.song_id::text) limit ?
      SQL
      needs_review + unanalysed + many_credits
    end

    def album_song_ids
      album_count = (@count * ALBUM_SHARE / ALBUM_TRACKS.minmax.sum.fdiv(2)).round
      album_ids = ids(<<~SQL, ALBUM_TRACKS.min, ALBUM_TRACKS.max, album_count)
        select a.id from albums a
        join songs s on s.album_id = a.id
        left join song_embeddings e on e.song_id = s.id
        where not a.compilation
        group by a.id
        having count(*) between ? and ? and count(e.id) = count(*)
        order by md5(a.id::text) limit ?
      SQL
      Song.where(album_id: album_ids).order(:album_id, :disc_number, :track_number).pluck(:id)
    end

    # Nearest songs by cosine similarity (the vectors are unit length, so a dot product), skipping
    # other copies of the same recording and capping how many links go to one artist.
    def neighbors(songs, embeddings)
      vectors = embeddings.to_h { |e| [ e["song_id"], e["embedding"] ] }
      info = songs.select { |s| vectors.key?(s["id"]) }.map do |s|
        artist = s["artist_id"] || s["id"]
        { id: s["id"], artist: artist, recording: s["musicbrainz_recording_id"], title_key: [ artist, s["title"].to_s.downcase ] }
      end
      scores = similarity(info.map { |i| vectors.fetch(i[:id]) })
      now = Time.now.utc.iso8601
      info.each_with_index.flat_map do |song, i|
        per_artist = Hash.new(0)
        seen = Set[song[:title_key]]
        ranked = (0...info.size).sort_by { |j| -scores[i][j] }
        links = []
        ranked.each do |j|
          other = info[j]
          next if j == i || (song[:recording] && other[:recording] == song[:recording]) || seen.include?(other[:title_key])
          next if per_artist[other[:artist]] >= NEIGHBORS_PER_ARTIST
          per_artist[other[:artist]] += 1
          seen << other[:title_key]
          links << { "song_id" => song[:id], "neighbor_id" => other[:id], "rank" => links.size,
                     "score" => scores[i][j].round(4), "created_at" => now, "updated_at" => now }
          break if links.size >= NEIGHBORS
        end
        links
      end
    end

    def similarity(vectors)
      scores = Array.new(vectors.size) { Array.new(vectors.size, 0.0) }
      vectors.each_with_index do |a, i|
        (i + 1...vectors.size).each do |j|
          b = vectors[j]
          dot = 0.0
          a.each_with_index { |x, k| dot += x * b[k] }
          scores[i][j] = scores[j][i] = dot
        end
      end
      scores
    end
  end
end
