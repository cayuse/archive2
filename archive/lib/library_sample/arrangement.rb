require "digest"

module LibrarySample
  # Writes a short piece of music for a song: which notes each instrument plays, and when.
  # Synth turns the notes into sound. Everything is decided by the song's genre, what the audio
  # analysis measured on the real recording, and the song id (so a song always gets the same tune):
  #
  #   genre          the style: drum pattern, bass line, how chords are played, lead instrument
  #   tempo_bpm      the tempo
  #   happiness      major or minor key
  #   energy         how busy the drums, bass and melody are
  #   danceability   four-on-the-floor / backbeat / half-time drums
  #   aggression     power chords (Synth also overdrives the guitar)
  #   instrumental   an instrument or a voice-like tone carries the melody
  #   speech         spoken-word tracks (see spoken?) get a murmuring voice and nothing else
  class Arrangement
    Note = Struct.new(:start, :length, :pitch, :voice, :level) # seconds, seconds, MIDI number (nil for drums)

    NEUTRAL = {
      "tempo_bpm" => 120.0, "energy" => 0.5, "danceability" => 0.5, "happiness" => 0.5, "aggression" => 0.5,
      "acousticness" => 0.5, "electronic" => 0.5, "instrumental" => 0.5, "speech" => 0.0
    }.freeze
    SPOKEN_GENRES = /audiobook|spoken|speech|podcast|comedy/i
    # First match wins, so "Blues/R&B" is blues and "Rock/Pop" is rock.
    GENRE_STYLES = {
      classical: /classical|opera|baroque|new age|soundtrack|easy listening|holiday|vocal/i,
      jazz: /jazz|swing|big band|lounge/i,
      blues: /blues/i,
      reggae: /reggae|ska|dub/i,
      rock: /rock|metal|punk|alternative/i,
      electronic: /electr|dance|techno|trance|house|industrial|hip hop|rap|r&b|soul|disco|pop/i,
      acoustic: /country|folk|bluegrass|gospel|religious|world|latin|children|oldies/i
    }.freeze
    MAJOR = [ 0, 2, 4, 5, 7, 9, 11 ].freeze
    MINOR = [ 0, 2, 3, 5, 7, 8, 10 ].freeze
    # Scale degrees of the five-note scale the melody walks, which sits well over any chord in the key.
    PENTATONIC = { major: [ 0, 1, 2, 4, 5 ], minor: [ 0, 2, 3, 4, 6 ] }.freeze
    # Chord roots as scale degrees, one per bar.
    PROGRESSIONS = {
      major: [ [ 0, 4, 5, 3 ], [ 0, 3, 4, 3 ], [ 0, 5, 3, 4 ], [ 0, 3, 0, 4 ] ],
      minor: [ [ 0, 5, 2, 6 ], [ 0, 3, 4, 0 ], [ 0, 6, 5, 6 ], [ 0, 5, 3, 4 ] ],
      jazz: [ [ 1, 4, 0, 5 ] ],
      blues: [ [ 0, 0, 0, 0, 3, 3, 0, 0, 4, 3, 0, 4 ] ]
    }.freeze
    LEADS = { rock: :guitar, blues: :guitar, electronic: :square, jazz: :sax, reggae: :keys, acoustic: :pluck, classical: :flute }.freeze
    EIGHTHS = [ 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5 ].freeze
    SIXTEENTHS = [ 0.25, 0.75, 1.25, 1.75, 2.25, 2.75, 3.25, 3.75 ].freeze

    attr_reader :style, :bpm, :notes, :seconds

    # Talking rather than music: a spoken-word genre, or a speech dial as high as the radio's own cutoff.
    def self.spoken?(genre, features)
      genre.to_s.match?(SPOKEN_GENRES) || features&.dig("speech").to_f >= SongRadio::SPEECH_CUTOFF
    end

    # The analysis sometimes hears double or half time; fold it into a range a band would play.
    def self.musical_tempo(tempo)
      tempo /= 2 while tempo > 180
      tempo *= 2 while tempo < 70
      tempo.round(1)
    end

    def initialize(song_id:, seconds:, features: nil, genre: nil)
      @f = NEUTRAL.merge((features || {}).slice(*NEUTRAL.keys).compact.transform_values(&:to_f))
      @rng = Random.new(Digest::MD5.hexdigest(song_id.to_s).to_i(16) % 2**32)
      @seconds = seconds
      @style = pick_style(genre)
      @bpm = self.class.musical_tempo(@f["tempo_bpm"])
      @beat = 60.0 / @bpm
      @swing = %i[jazz blues].include?(@style)
      @minor = @style != :blues && @f["happiness"] < 0.5
      @scale = @minor ? MINOR : MAJOR
      @root = 40 + @rng.rand(12) # bass register, E2 to D#3
      @progression = progression
      @bars = [ (seconds / (4 * @beat)).floor, 2 ].max
      @intro_bars = @bars >= 10 ? 2 : 1
      @notes = []
      compose
    end

    # How hard Synth overdrives the guitar: 0 is clean.
    def drive
      %i[rock blues].include?(@style) ? ((@f["aggression"] - 0.4) * 10).clamp(0, 6) : 0
    end

    private

    def pick_style(genre)
      return :spoken if self.class.spoken?(genre, @f)
      named = GENRE_STYLES.find { |_style, pattern| genre.to_s.match?(pattern) }&.first
      return named if named
      return :electronic if @f["electronic"] >= 0.7
      return (@f["energy"] < 0.3 ? :classical : :acoustic) if @f["acousticness"] >= 0.7
      :rock
    end

    def progression
      family = PROGRESSIONS.key?(@style) ? @style : (@minor ? :minor : :major)
      PROGRESSIONS.fetch(family).sample(random: @rng)
    end

    def compose
      motifs = { verse: motif, chorus: motif }
      @bars.times do |bar|
        @at = bar * 4 * @beat
        section = section_for(bar)
        degree = @progression[bar % @progression.size]
        drums(bar, section)
        bass(degree, @progression[(bar + 1) % @progression.size])
        chords(degree, section)
        melody(bar, section, motifs)
      end
    end

    def section_for(bar)
      return :intro if bar < @intro_bars
      ((bar - @intro_bars) / 4).even? ? :verse : :chorus
    end

    def add(beat, length, pitch, voice, level)
      beat += 0.17 if @swing && (beat % 1) == 0.5
      start = @at + beat * @beat
      @notes << Note.new(start, length * @beat, pitch, voice, level) if start < @seconds
    end

    def pitch(degree, octave = 0)
      @root + @scale[degree % 7] + 12 * (degree / 7 + octave)
    end

    def chord(degree, octave = 1)
      steps = %i[jazz blues].include?(@style) ? [ 0, 2, 4, 6 ] : [ 0, 2, 4 ]
      steps.map { |step| pitch(degree + step, octave) }
    end

    def drums(bar, section)
      return if %i[spoken classical].include?(@style) || (@style == :acoustic && @f["energy"] < 0.3)
      kicks, snares, hats, rides = drum_pattern
      level = 0.5 + 0.5 * @f["energy"]
      if section == :intro
        kicks, snares = [ 0 ], []
      elsif bar % 4 == 3 && @f["energy"] > 0.5
        snares += [ 3, 3.25, 3.5, 3.75 ] # a fill into the next section
      end
      kicks.each { |b| add(b, 1, nil, :kick, 0.9 * level) }
      snares.uniq.each { |b| add(b, 1, nil, :snare, 0.5 * level) }
      hats.each { |b| add(b, 1, nil, :hat, 0.18 * level) }
      rides.each { |b| add(b, 1, nil, :ride, 0.15 * level) }
    end

    # [kick beats, snare beats, hi-hat beats, ride beats] within one bar
    def drum_pattern
      case @style
      when :electronic
        if @f["danceability"] >= 0.5
          [ [ 0, 1, 2, 3 ], [ 1, 3 ], [ 0.5, 1.5, 2.5, 3.5 ] + (@f["energy"] > 0.7 ? SIXTEENTHS : []), [] ]
        else
          [ [ 0, 1.75, 2.5 ], [ 1, 3 ], EIGHTHS, [] ]
        end
      when :jazz then [ [ 0 ], [], [ 1, 3 ], [ 0, 1, 1.5, 2, 3, 3.5 ] ]
      when :reggae then [ [ 2 ], [ 2 ], EIGHTHS, [] ]
      when :acoustic then [ [ 0, 2 ], [ 1, 3 ], EIGHTHS, [] ]
      else
        [ [ 0, 2 ] + (@f["energy"] > 0.6 ? [ 2.5 ] : []), @f["danceability"] < 0.2 ? [ 2 ] : [ 1, 3 ], EIGHTHS, [] ]
      end
    end

    def bass(degree, next_degree)
      root = pitch(degree)
      case @style
      when :spoken then nil
      when :classical then add(0, 4, root, :bass, 0.3)
      when :jazz # walking: root, third, fifth, then a step below the next chord
        [ root, pitch(degree + 2), pitch(degree + 4), pitch(next_degree) - 1 ].each_with_index { |p, b| add(b, 0.95, p, :bass, 0.45) }
      when :reggae
        [ [ 0, 1, root ], [ 1.5, 0.5, pitch(degree + 4) ], [ 2.5, 1, root ] ].each { |b, len, p| add(b, len, p, :bass, 0.5) }
      when :acoustic # root and fifth, the country two-step
        add(0, 1.9, root, :bass, 0.45)
        add(2, 1.9, pitch(degree + 4) - 12, :bass, 0.45)
      when :electronic
        [ 0, 0.75, 1.5, 2, 2.75, 3.5 ].each { |b| add(b, 0.5, [ 1.5, 3.5 ].include?(b) ? root + 12 : root, :bass, 0.5) }
      else
        beats = @f["energy"] > 0.5 ? EIGHTHS : [ 0, 2 ]
        beats.each { |b| add(b, 4.0 / beats.size * 0.9, root, :bass, 0.45) }
      end
    end

    def chords(degree, section)
      tones = chord(degree)
      case @style
      when :spoken then nil
      when :classical
        tones.each { |p| add(0, 4, p, :strings, 0.1) }
        EIGHTHS.each_with_index { |b, i| add(b, 1, tones[[ 0, 1, 2, 1 ][i % 4]] + 12, :pluck, 0.16) }
      when :acoustic
        EIGHTHS.each_with_index { |b, i| add(b, 1, tones[[ 0, 1, 2, 1 ][i % 4]], :pluck, 0.22) }
      when :jazz then [ 1.5, 3 ].each { |b| tones.each { |p| add(b, 0.4, p, :keys, 0.14) } }
      when :reggae then [ 1, 3 ].each { |b| tones.each { |p| add(b, 0.3, p, :keys, 0.2) } } # the offbeat skank
      when :electronic
        tones.each { |p| add(0, 4, p, :pad, 0.11) }
        add(0, 4, tones.first + 12, :pad, 0.08) if section == :chorus
      else
        root = pitch(degree, 1)
        tones = [ root, root + 7, root + 12 ] if @f["aggression"] > 0.5 # power chord
        beats = @f["energy"] > 0.6 ? EIGHTHS : [ 0 ]
        beats.each { |b| tones.each { |p| add(b, 4.0 / beats.size, p, :guitar, 0.15) } }
      end
    end

    # A two-bar phrase on the pentatonic scale, as [beat within the two bars, length, scale step].
    # The verse repeats one phrase and the chorus another, which is what makes it sound like a tune.
    def motif
      density = @style == :spoken ? 0.7 : 0.3 + 0.3 * @f["energy"]
      step = 2 + @rng.rand(3)
      starts = (0...16).select { |eighth| eighth.zero? || @rng.rand < density }
      starts.each_with_index.map do |eighth, i|
        step = (step + @rng.rand(-2..2)).clamp(0, @style == :spoken ? 3 : 9)
        following = starts[i + 1] || 16
        [ eighth / 2.0, [ (following - eighth) / 2.0, 2 ].min * 0.95, step ]
      end
    end

    def melody(bar, section, motifs)
      return if section == :intro
      voice = @style == :spoken || @f["instrumental"] < 0.6 ? :voice : LEADS.fetch(@style)
      scale = PENTATONIC.fetch(@minor ? :minor : :major)
      half = (bar - @intro_bars) % 2 # which bar of the two-bar phrase this is
      motifs.fetch(section).each do |beat, length, step|
        next unless (beat / 4).floor == half
        degree = scale[step % 5] + 7 * (step / 5)
        add(beat - 4 * half, length, pitch(degree, @style == :spoken ? 1 : 2), voice, section == :chorus ? 0.34 : 0.28)
      end
    end
  end
end
