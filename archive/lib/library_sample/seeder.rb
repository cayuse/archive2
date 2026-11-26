require "json"
require "tmpdir"
require "zlib"

module LibrarySample
  # Loads the fixture written by Exporter into the current database and gives every song a
  # stand-in audio file: an AI-generated clip when there is one for the song or its genre,
  # otherwise music composed on the spot (see AudioSynth).
  #
  # Safe to rerun: rows that exist are left alone, and only songs that still have no audio get
  # a file (refresh_audio makes all of it again, for when better clips have been generated).
  # Rows keep their original ids, so links between them hold.
  #
  # Rows go in with insert_all on purpose: no model callbacks, so nothing is queued for audio
  # processing and no sync changes are recorded.
  class Seeder
    PLAYLIST_SIZE = 40
    RENDER_THREADS = 4
    # name => [dial, :high or :low]
    PLAYLISTS = {
      "Sample: High Energy" => [ "energy", :high ],
      "Sample: Mellow" => [ "energy", :low ],
      "Sample: Dance Floor" => [ "danceability", :high ],
      "Sample: Acoustic" => [ "acousticness", :high ]
    }.freeze

    def initialize(path:, user:, clips:, limit: nil, refresh_audio: false, synth: AudioSynth.new, out: $stdout)
      @path = path
      @clips = clips
      @refresh_audio = refresh_audio
      @user = user
      @limit = limit
      @synth = synth
      @out = out
    end

    def call
      data = JSON.parse(Zlib::GzipReader.open(@path, &:read))
      songs = @limit ? data.fetch("songs").first(@limit) : data.fetch("songs")
      song_ids = songs.map { |s| s["id"] }.to_set
      features = data.fetch("song_audio_features").select { |f| song_ids.include?(f["song_id"]) }

      ActiveRecord::Base.transaction { insert_rows(data, songs, song_ids, features) }
      remove_audio(song_ids) if @refresh_audio
      made = attach_audio(songs, features.index_by { |f| f["song_id"] }, data)
      build_playlists(song_ids) if @user
      @out.puts "library sample: #{songs.size} songs in fixture slice, #{made} audio files made; " \
                "database now has songs=#{Song.count} artists=#{Artist.count} albums=#{Album.count} " \
                "genres=#{Genre.count} analysed=#{SongAudioFeature.count} neighbours=#{SongNeighbor.count}"
    end

    private

    def insert_rows(data, songs, song_ids, features)
      for_songs = ->(table) { data.fetch(table).select { |r| song_ids.include?(r["song_id"]) } }
      credits = for_songs.call("song_artist_credits")
      albums = data.fetch("albums").select { |a| songs.any? { |s| s["album_id"] == a["id"] } }
      artist_ids = (songs + albums + credits).filter_map { |r| r["artist_id"] }.to_set
      genre_id = insert_genres(data.fetch("genres"))

      insert(Artist, data.fetch("artists").select { |a| artist_ids.include?(a["id"]) })
      insert(Album, albums)
      insert(Song, songs.map do |s|
        s.merge("genre_id" => genre_id[s["genre_id"]], "user_id" => @user&.id,
                "duration" => AudioSynth.clip_seconds(s["duration"]),
                "file_format" => AudioSynth.format_for(s["file_format"]))
      end)
      insert(SongArtistCredit, credits)
      insert(SongFileTag, for_songs.call("song_file_tags").map do |t|
        t.merge("duration_seconds" => AudioSynth.clip_seconds(t["duration_seconds"]), "blob_key" => nil, "blob_checksum" => nil)
      end)
      insert(SongAudioFeature, features)
      insert(SongEmbedding, for_songs.call("song_embeddings"))
      insert(SongNeighbor, for_songs.call("song_neighbors").select { |n| song_ids.include?(n["neighbor_id"]) })
      insert(GenreAffinity, data.fetch("genre_affinities").filter_map do |a|
        ids = a.values_at("genre_id", "related_genre_id").map { |id| genre_id[id] }
        a.merge("genre_id" => ids[0], "related_genre_id" => ids[1]) if ids.all?
      end)
    end

    def insert(model, rows)
      rows.each_slice(500) { |slice| model.insert_all(slice) }
    end

    # Genre names are unique, and a database may already have "Rock" under another id.
    # Returns fixture genre id => the id that name has in this database.
    def insert_genres(rows)
      insert(Genre, rows)
      by_name = Genre.where(name: rows.map { |g| g["name"] }).pluck(:name, :id).to_h
      rows.to_h { |g| [ g["id"], by_name.fetch(g["name"]) ] }
    end

    # For when better clips have been generated since the last run: every song gets its audio made again.
    def remove_audio(song_ids)
      attachments = ActiveStorage::Attachment.where(record_type: "Song", name: "audio_file", record_id: song_ids.to_a)
      blobs = ActiveStorage::Blob.where(id: attachments.pluck(:blob_id)).to_a
      attachments.delete_all
      blobs.each(&:purge)
    end

    def attach_audio(songs, features, data)
      have = ActiveStorage::Attachment.where(record_type: "Song", name: "audio_file", record_id: songs.map { |s| s["id"] }).pluck(:record_id).to_set
      todo = songs.reject { |s| have.include?(s["id"]) }
      return 0 if todo.empty?

      artist_name = data.fetch("artists").to_h { |a| [ a["id"], a["name"] ] }
      album_title = data.fetch("albums").to_h { |a| [ a["id"], a["title"] ] }
      genre_name = data.fetch("genres").to_h { |g| [ g["id"], g["name"] ] }
      done = 0
      Dir.mktmpdir do |dir|
        # Making the audio is the slow part (about a second a song), so do a few at once; rows go in one at a time.
        todo.each_slice(RENDER_THREADS) do |batch|
          renders = batch.map do |song|
            Thread.new { render(song, dir, features[song["id"]], artist_name, album_title, genre_name) }
          end
          batch.zip(renders.map(&:value)).each do |song, file|
            attach(song, file)
            File.delete(file)
          end
          done += batch.size
          @out.puts "  audio #{done}/#{todo.size}" if (done % 100) < RENDER_THREADS
        end
      end
      todo.size
    end

    def render(song, dir, features, artist_name, album_title, genre_name)
      format = AudioSynth.format_for(song["file_format"])
      @synth.render(path: File.join(dir, "#{song['id']}.#{format}"), song_id: song["id"], file_format: format,
                    features: features, seconds: AudioSynth.clip_seconds(song["duration"]),
                    clip: @clips.pick(song_id: song["id"], genre: genre_name[song["genre_id"]], features: features),
                    tags: { "title" => song["title"], "artist" => song["artist_credit"] || artist_name[song["artist_id"]],
                            "album" => album_title[song["album_id"]], "genre" => genre_name[song["genre_id"]],
                            "track" => song["track_number"] })
    end

    def attach(song, file)
      format = AudioSynth.format_for(song["file_format"])
      filename = song["original_filename"].presence || "#{song['title']}.#{format}"
      blob = File.open(file, "rb") do |io|
        ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: AudioSynth.content_type(format), identify: false)
      end
      ActiveStorage::Attachment.insert_all([ { name: "audio_file", record_type: "Song", record_id: song["id"], blob_id: blob.id, created_at: Time.current } ])
      seconds = AudioSynth.clip_seconds(song["duration"])
      Song.where(id: song["id"]).update_all(file_size: blob.byte_size, duration: seconds)
      SongFileTag.where(song_id: song["id"]).update_all(blob_key: blob.key, blob_checksum: blob.checksum, duration_seconds: seconds)
    end

    def build_playlists(song_ids)
      PLAYLISTS.each do |name, (dial, direction)|
        playlist = Playlist.find_or_create_by!(name: name, user: @user)
        order = direction == :high ? { dial => :desc } : { dial => :asc }
        picks = SongAudioFeature.where(song_id: song_ids.to_a).where("speech < 0.9").order(order).limit(PLAYLIST_SIZE).pluck(:song_id)
        now = Time.current
        rows = picks.each_with_index.map { |id, i| { playlist_id: playlist.id, song_id: id, position: i + 1, created_at: now, updated_at: now } }
        PlaylistsSong.insert_all(rows) if rows.any?
      end
    end
  end
end
