require "json"
require "zlib"

module LibrarySample
  # Writes one music-generation prompt per song in the fixture, for an AI music generator to turn
  # into db/library_sample/clips/<song id>.mp3. Each prompt describes a made-up song in the real
  # song's genre, tempo and mood, taken from the audio analysis. It never names the real title,
  # artist or album: the generator is asked for something new in a style, not a copy of anything.
  class PromptWriter
    # dial => [words when it is low, words when it is high]; the middle says nothing.
    DIAL_WORDS = {
      "energy" => [ "calm, quiet and gentle", "high energy, loud and driving" ],
      "danceability" => [ "loose, free rhythm", "a strong steady beat you can dance to" ],
      "happiness" => [ "sad, melancholy mood", "happy, uplifting mood" ],
      "aggression" => [ "soft and tender", "aggressive and heavy" ],
      "acousticness" => [ nil, "acoustic instruments" ],
      "electronic" => [ nil, "synthesizers and drum machines" ]
    }.freeze
    LOW = 0.3
    HIGH = 0.7
    INSTRUMENTAL = 0.6
    RAP_GENRES = /hip hop|rap/i

    def initialize(fixture_path:, path:, out: $stdout)
      @fixture_path = fixture_path
      @path = path
      @out = out
    end

    def call
      data = JSON.parse(Zlib::GzipReader.open(@fixture_path, &:read))
      features = data.fetch("song_audio_features").index_by { |f| f["song_id"] }
      genres = data.fetch("genres").to_h { |g| [ g["id"], g["name"] ] }
      rows = data.fetch("songs").map { |song| row(song, genres[song["genre_id"]], features[song["id"]]) }
      File.write(@path, rows.map { |r| JSON.generate(r) }.join("\n") + "\n")
      @out.puts "wrote #{rows.size} prompts to #{@path}"
    end

    def row(song, genre, features)
      vocals = vocals(genre, features)
      bpm = Arrangement.musical_tempo(features&.dig("tempo_bpm") || 120.0).round
      seconds = AudioSynth.clip_seconds(song["duration"])
      { "file" => "#{song['id']}.mp3", "seconds" => seconds, "genre" => genre, "bpm" => bpm, "vocals" => vocals,
        "prompt" => prompt(genre, bpm, seconds, vocals, features) }
    end

    private

    def vocals(genre, features)
      return "spoken" if Arrangement.spoken?(genre, features)
      return "rapped" if genre.to_s.match?(RAP_GENRES)
      features && features["instrumental"].to_f >= INSTRUMENTAL ? "instrumental" : "sung"
    end

    def prompt(genre, bpm, seconds, vocals, features)
      style = genre ? "an original #{genre} piece" : "an original piece of music"
      traits = DIAL_WORDS.filter_map do |dial, (low, high)|
        value = features&.dig(dial)
        next unless value
        value <= LOW ? low : (value >= HIGH ? high : nil)
      end
      voice = { "spoken" => "A person speaking original made-up words, little or no music",
                "instrumental" => "Instrumental, no vocals",
                "rapped" => "A rapper performing original made-up lyrics",
                "sung" => "A lead vocal singing original made-up lyrics" }.fetch(vocals)
      "#{seconds} seconds of #{style}, about #{bpm} BPM. #{traits.join(', ').capitalize.presence&.concat('. ')}#{voice}. " \
        "Entirely new: do not imitate any existing song, melody, lyrics or artist."
    end
  end
end
