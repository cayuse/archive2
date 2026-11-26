# What GET /api/v1/analysis answers: a description of the analysis API complete enough for a
# program (or a model writing one) to do the job from it alone. Keep it in step with
# Api::V1::AnalysisController and AnalysisWriter: this text is the contract.
module AnalysisApiGuide
  DIAL_PHRASES = {
    "energy" => [ [ "high energy music, loud, fast and intense", "an energetic, driving, powerful track" ],
                  [ "calm, quiet, slow and gentle music", "a soft, relaxing, mellow track" ] ],
    "danceability" => [ [ "dance music with a strong steady beat", "a groovy track that makes you want to dance" ],
                        [ "music with no beat, free rhythm", "ambient or orchestral music you cannot dance to" ] ],
    "happiness" => [ [ "happy, cheerful, uplifting music", "a joyful feel-good song" ],
                     [ "sad, melancholic, sorrowful music", "a dark, depressing, gloomy song" ] ],
    "aggression" => [ [ "aggressive, angry, heavy music", "harsh distorted guitars and shouting" ],
                      [ "gentle, tender, peaceful music", "a sweet soft lullaby" ] ],
    "acousticness" => [ [ "acoustic music played on acoustic instruments", "unplugged acoustic guitar or piano" ],
                        [ "electronic music made with synthesizers", "heavily produced electric and electronic sound" ] ],
    "electronic" => [ [ "electronic music with synthesizers and drum machines", "techno, house or electro" ],
                      [ "a live band with guitars, bass and drums", "acoustic or orchestral instruments" ] ],
    "instrumental" => [ [ "instrumental music with no vocals", "music without any singing" ],
                        [ "a song with a lead singer", "vocals and singing" ] ],
    "speech" => [ [ "a person speaking, spoken word", "audiobook narration, someone talking without music" ],
                  [ "music", "a song with instruments" ] ]
  }.freeze

  def self.build(base_url)
    model, dimensions = AnalysisWriter.library_model
    url = ->(path) { "#{base_url}/api/v1/analysis#{path}" }
    {
      name: "The Archive: sound analysis API",
      purpose: "The Archive is a music library whose radio stations pick songs by how they sound. A song can only be picked once it has " \
               "been analysed: an embedding (a vector from an audio model), eight 0..1 \"dials\" (energy, danceability, ...), a few signal " \
               "measurements (tempo, loudness, ...) and a list of the songs that sound most like it. The server does not analyse audio. " \
               "Your job is to do that for songs that have none yet, on your own machine, and write the results back through this API.",
      authentication: "Send the key with every request: `Authorization: Bearer <key>`. The key opens only the endpoints listed here. " \
                      "It cannot read users, playlists or settings, and cannot add, change or delete songs or files.",
      library: { analysis_model: model, embedding_dimensions: dimensions, songs_analysed: SongEmbedding.count,
                 songs_awaiting_analysis: Song.awaiting_analysis.count },
      conventions: [
        "All ids are UUID strings. Times are ISO 8601 UTC.",
        "Lists are paged. Pass `limit` (see each endpoint for its maximum) and, to continue, `after` = the `next_after` value of the previous page. " \
        "A page with `next_after: null` is the last one.",
        "`since` (ISO 8601 time) limits a list to rows created or changed at or after that time. Remember the `server_time` of your last run and " \
        "pass it as `since` on the next to learn what is new.",
        "Writes are JSON bodies (`Content-Type: application/json`). A write is all-or-nothing: if any item in the request is invalid, nothing is " \
        "written and the response is HTTP 422 with `problems`, a list of what to fix. Fix and resend the whole request.",
        "Errors: 401 no or bad key, 404 no such thing, 422 invalid request (see `problems`), 413 request too large."
      ],
      workflow: [
        "1. GET #{url.call('/status')} to see how much is waiting.",
        "2. GET #{url.call('/pending')} for the songs awaiting analysis. For each, GET its `audio_url` (the audio file itself).",
        "3. Analyse each file with the library's model (#{model.inspect}; embeddings of #{dimensions.inspect} numbers, L2-normalised). Compute the signal " \
        "features and the eight dials (see `definitions`). The dials are percentiles against the whole library, so you need the library's embeddings: " \
        "GET #{url.call('/embeddings')} once and keep a local copy; later runs only need `since`.",
        "4. POST #{url.call('/results')} with features and embedding for the new songs. After this they no longer appear in /pending.",
        "5. Compute each new song's sound-alike list (see `definitions.neighbors`) and POST #{url.call('/neighbors')}. Also resend the list of any " \
        "existing song that a new song now belongs in: a new song that nobody lists as a neighbour is never reached by a station.",
        "6. Optional, after a large batch: recompute and POST #{url.call('/genre_affinities')}."
      ],
      endpoints: [
        { method: "GET", path: "/api/v1/analysis", does: "This description." },
        { method: "GET", path: "/api/v1/analysis/status", does: "Counts (songs, analysed, awaiting), the library's model and vector size, when analysis was last written, and `server_time`." },
        { method: "GET", path: "/api/v1/analysis/pending", params: "limit (max 500, default 100), after",
          does: "Songs with an audio file and no analysis, oldest first. Each has the same fields as /songs plus `audio_url`." },
        { method: "GET", path: "/api/v1/analysis/songs", params: "limit (max 2000, default 500), after, since, ids (comma-separated, max 200)",
          does: "Every song: id, title, artist {id, name}, album {id, title}, genre {id, name}, duration (seconds), file_format, byte_size, " \
                "musicbrainz_recording_id, analysed (true/false), created_at, updated_at. Needed for the neighbour rules and genre affinities." },
        { method: "GET", path: "/api/v1/analysis/songs/:id/audio", does: "The song's audio file, as stored (mp3, flac, m4a, ogg ...). Read-only." },
        { method: "GET", path: "/api/v1/analysis/features", params: "limit (max 5000, default 1000), after, since, ids",
          does: "Stored features per analysed song: the eight dials, the signal measurements, analysis_model, analyzed_at." },
        { method: "GET", path: "/api/v1/analysis/embeddings", params: "limit (max 2000, default 500), after, since, ids",
          does: "Stored embeddings: song_id, dimensions, and `embedding_b64` (the vector as little-endian float32, base64). " \
                "numpy: np.frombuffer(base64.b64decode(s), dtype='<f4')." },
        { method: "GET", path: "/api/v1/analysis/neighbors", params: "ids (comma-separated, max 200; required)",
          does: "The stored sound-alike list of each given song: [{id, score}, ...] best first." },
        { method: "GET", path: "/api/v1/analysis/genres", does: "Every genre: id, name, songs (how many songs carry it)." },
        { method: "GET", path: "/api/v1/analysis/genre_affinities", does: "The stored genre adjacency: [{genre_id, related_genre_id, score}, ...]." },
        { method: "POST", path: "/api/v1/analysis/results",
          body: { model: model, replace: false,
                  songs: [ { song_id: "<uuid>", features: { energy: 0.5, "...": "the other seven dials", tempo_bpm: 120.0, "....": "other signal features" },
                             embedding: "[#{dimensions} numbers]  (or embedding_b64 instead)" } ] },
          does: "Stores features and embedding for up to #{AnalysisWriter::MAX_SONGS} songs. Rules: `model` must be the library's model; every song must " \
                "exist and have audio; all eight dials are required, each 0..1; signal features are optional but must be in range when given; the " \
                "embedding must have exactly #{dimensions.inspect} finite numbers. A song that already has analysis is refused unless `replace` is true." },
        { method: "POST", path: "/api/v1/analysis/neighbors",
          body: { lists: [ { song_id: "<uuid>", neighbors: [ { id: "<uuid>", score: 0.93 }, { id: "<uuid>", score: 0.91 } ] } ] },
          does: "Replaces the sound-alike list of each given song (up to #{AnalysisWriter::MAX_LISTS} songs per request, 1 to " \
                "#{AnalysisWriter::MAX_NEIGHBORS} neighbours each; the library uses 30). Rules: the song and every neighbour must already have an " \
                "embedding stored (POST /results first); no song is its own neighbour; no repeats; scores from -1 to 1, best first." },
        { method: "POST", path: "/api/v1/analysis/genre_affinities",
          body: { affinities: [ { genre_id: "<uuid>", related_genre_id: "<uuid>", score: 2.2 } ], allow_shrink: false },
          does: "Replaces the WHOLE genre adjacency table with what you send. Refused if it would shrink the table to under half its size, " \
                "unless `allow_shrink` is true. Do not call it with a partial list." }
      ],
      definitions: {
        embedding: "The audio embedding from #{model.inspect} (CLAP audio tower), L2-normalised. The existing library was analysed with " \
                   "transformers 4.46.3; do not substitute \"laion/larger_clap_music\", whose text side is broken. How the audio was windowed for " \
                   "the existing library is in the repository's library_tools/scripts/analyze_audio.py; follow it so new vectors are comparable.",
        signal_features: {
          analyzed_seconds: "how much of the file was analysed, seconds (0.1 to 100000)",
          loudness_db: "integrated loudness, dB (-150 to 30)", peak_db: "peak level, dB (-150 to 30)", tempo_bpm: "tempo, beats per minute (20 to 400)",
          brightness_hz: "spectral centroid, Hz (0 to 30000)", onset_strength: "mean onset strength (0 to 1000)"
        },
        dials: {
          what: "Eight numbers from 0 to 1. Each is a PERCENTILE within the library: 0.9 means \"more of this than 90% of the archive\". Stations and " \
                "search rely on that meaning, so a raw similarity must never be stored as a dial.",
          how: "For each dial, embed its phrases with the model's TEXT tower (L2-normalised). raw = mean(similarity of the song's embedding to the " \
               "\"towards\" phrases) - mean(similarity to the \"away\" phrases). The dial is the percentile of that raw value among the raw values of " \
               "every song in the library (compute those from /embeddings). For a new song, rank it against the existing library; do not rewrite " \
               "existing songs' dials unless you are deliberately rebuilding the whole library.",
          energy_is_blended: "energy = percentile(0.6 * energy_dial + 0.25 * percentile(loudness_db) + 0.15 * percentile(onset_strength)), " \
                             "each percentile taken across the library.",
          phrases: DIAL_PHRASES.transform_values { |towards, away| { towards: towards, away: away } }
        },
        neighbors: "For each song, the 30 most similar other songs by cosine similarity of embeddings (score = the cosine), best first, with three " \
                   "rules applied while filling the list: skip another copy of the same recording (same musicbrainz_recording_id); skip a song " \
                   "whose artist and lower-cased title equal the song's own or one already in the list; take at most 4 songs by any one artist.",
        genre_affinities: "Genre A is related to genre B when A's songs have B-tagged neighbours clearly more often than chance. score is that lift. " \
                          "The existing computation is at the end of library_tools/scripts/build_vectors.py."
      },
      limits: { results_songs_per_request: AnalysisWriter::MAX_SONGS, neighbor_lists_per_request: AnalysisWriter::MAX_LISTS,
                neighbors_per_song: AnalysisWriter::MAX_NEIGHBORS, request_body: "keep each request under 20 MB" },
      safety: "This key can write only the four analysis tables, and every write is validated as described. It is still your data that stations " \
              "play from: work in small batches, check a batch reads back as you sent it (GET /features, /neighbors with ids) before sending the " \
              "next, and never use `replace` or `allow_shrink` unless that is exactly what you mean."
    }
  end
end
