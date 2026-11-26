require "open3"

module LibrarySample
  # Makes a short stand-in audio file for a song.
  #
  # Given a clip from the AI-generated pack (ClipLibrary), it cuts that to length, nudges it
  # towards the song's measured tempo and tags it. Without one it makes the music itself:
  # Arrangement writes a piece in the song's genre, tempo and mood, Synth plays it, and the
  # real recording's brightness and loudness shape the final sound.
  #
  # Nothing here is a real recording, so the files are safe to share and play anywhere.
  class AudioSynth
    CLIP_SECONDS = (15..30)
    # How far a generated clip may be sped up or slowed down before it starts to sound wrong.
    TEMPO_STRETCH = (0.87..1.15)
    FORMATS = {
      "mp3" => { codec: %w[-c:a libmp3lame -b:a 128k], content_type: "audio/mpeg" },
      "m4a" => { codec: %w[-c:a aac -b:a 128k], content_type: "audio/mp4" },
      "flac" => { codec: %w[-c:a flac], content_type: "audio/flac" }
    }.freeze
    DEFAULT_FORMAT = "mp3"
    DEFAULT_BRIGHTNESS_HZ = 2500.0
    DEFAULT_LOUDNESS_DB = -14.0

    # An eighth of the real length: short enough to watch a queue advance, still varied.
    def self.clip_seconds(real_duration)
      (real_duration.to_i / 8).clamp(CLIP_SECONDS.min, CLIP_SECONDS.max)
    end

    def self.format_for(file_format)
      FORMATS.key?(file_format) ? file_format : DEFAULT_FORMAT
    end

    def self.content_type(file_format)
      FORMATS.fetch(format_for(file_format)).fetch(:content_type)
    end

    # features: a song_audio_features row as a hash, or nil for a song that was never analysed.
    # tags: { "title" => ..., "artist" => ..., "genre" => ... } written into the file.
    # clip: a ClipLibrary::Clip to use instead of composing, or nil.
    def render(path:, song_id:, file_format:, seconds:, features:, tags: {}, clip: nil)
      wav = "#{path}.wav"
      if clip
        source, effects = clip.path, clip_filters(clip, features, seconds)
      else
        arrangement = Arrangement.new(song_id: song_id, seconds: seconds, features: features, genre: tags["genre"])
        synthesize(arrangement, wav)
        source, effects = wav, filters(features, seconds)
      end
      args = [ "ffmpeg", "-loglevel", "error", "-y", "-i", source, "-af", effects, "-t", seconds.to_s, "-ar", "44100",
               *tags.compact.flat_map { |key, value| [ "-metadata", "#{key}=#{value}" ] },
               *FORMATS.fetch(self.class.format_for(file_format)).fetch(:codec), path ]
      _out, err, status = Open3.capture3(*args)
      raise "ffmpeg failed for song #{song_id}: #{err}" unless status.success?
      path
    ensure
      File.delete(wav) if wav && File.exist?(wav)
    end

    def clip_filters(clip, features, seconds)
      stretch = clip.bpm ? Arrangement.musical_tempo(features&.dig("tempo_bpm") || clip.bpm) / clip.bpm : 1.0
      tempo = stretch != 1.0 && TEMPO_STRETCH.cover?(stretch) ? "atempo=#{stretch.round(3)}," : ""
      "#{tempo}afade=t=out:st=#{seconds - 1}:d=1"
    end

    def filters(features, seconds)
      brightness = features&.dig("brightness_hz") || DEFAULT_BRIGHTNESS_HZ
      loudness = features&.dig("loudness_db") || DEFAULT_LOUDNESS_DB
      cutoff = (brightness * 2.5).clamp(1500, 10_000).round
      gain = (loudness + 14).clamp(-12, 4).round(1)
      "lowpass=f=#{cutoff},aecho=0.8:0.6:45:0.2,volume=#{gain}dB,alimiter=limit=0.9,aformat=channel_layouts=mono,afade=t=out:st=#{seconds - 1}:d=1"
    end

    private

    # The synthesis is a second of pure Ruby arithmetic. Doing it in a child process lets the
    # seeder render several songs at once (threads alone would take turns on one core).
    def synthesize(arrangement, wav)
      pid = fork do
        File.binwrite(wav, Synth.new.wav(arrangement.notes, arrangement.seconds, drive: arrangement.drive))
        exit!(0)
      end
      _pid, status = Process.wait2(pid)
      raise "synthesis failed" unless status.success?
    end
  end
end
