module LibrarySample
  # A small software synthesizer: turns Arrangement notes into mono 16-bit audio.
  # Pitched instruments are wavetables (a few harmonics each) with an attack, a decay and a
  # release; the drum kit is a swept sine (kick) and shaped noise (snare, hi-hat, ride).
  # Plain Ruby and no gems, so it runs anywhere the app does. About a second per song.
  class Synth
    RATE = 22_050
    TABLE_SIZE = 2048
    TABLE_MASK = TABLE_SIZE - 1
    # harmonics: level of each overtone, lowest first. attack and release in seconds,
    # decay as a rate (0 holds the note, 5 is a pluck), vibrato as a fraction of the pitch.
    Voice = Struct.new(:harmonics, :attack, :decay, :release, :vibrato)
    VOICES = {
      bass: Voice.new([ 1, 0.5, 0.25 ], 0.005, 1.5, 0.03, 0),
      pad: Voice.new([ 1, 0.5, 0.33, 0.25, 0.2, 0.17 ], 0.15, 0.0, 0.2, 0),
      strings: Voice.new([ 1, 0.5, 0.33, 0.25, 0.2 ], 0.08, 0.0, 0.15, 0.004),
      pluck: Voice.new([ 1, 0.4, 0.2, 0.1, 0.05 ], 0.003, 5.0, 0.05, 0),
      keys: Voice.new([ 1, 0.3, 0, 0.1 ], 0.005, 3.0, 0.04, 0),
      guitar: Voice.new([ 1, 0.5, 0.33, 0.25, 0.2, 0.17, 0.14, 0.12 ], 0.005, 1.2, 0.03, 0),
      square: Voice.new([ 1, 0, 0.33, 0, 0.2 ], 0.01, 0.8, 0.03, 0),
      sax: Voice.new([ 1, 0.6, 0.4, 0.2, 0.1 ], 0.03, 0.4, 0.05, 0.004),
      flute: Voice.new([ 1, 0.1 ], 0.05, 0.2, 0.06, 0.003),
      voice: Voice.new([ 1, 0.3, 0.15 ], 0.06, 0.3, 0.08, 0.006)
    }.freeze
    # name => [seconds, decay rate, body tone in Hz or nil, bright (high-passed noise)]
    NOISE_DRUMS = { snare: [ 0.2, 18.0, 190.0, false ], hat: [ 0.06, 60.0, nil, true ], ride: [ 0.3, 12.0, nil, true ] }.freeze
    VIBRATO_HZ = 5.5
    SINE = Array.new(TABLE_SIZE) { |i| Math.sin(2 * Math::PI * i / TABLE_SIZE) }.freeze
    NOISE = Random.new(1).then { |rng| Array.new(RATE) { rng.rand * 2 - 1 } }.freeze
    TABLES = VOICES.transform_values do |voice|
      table = Array.new(TABLE_SIZE) do |i|
        voice.harmonics.each_with_index.sum { |level, h| level * Math.sin(2 * Math::PI * (h + 1) * i / TABLE_SIZE) }
      end
      peak = table.map(&:abs).max
      table.map { |x| x / peak }.freeze
    end.freeze

    # A complete WAV file, as a binary string.
    def wav(notes, seconds, drive: 0)
      data = samples(notes, seconds, drive: drive).map { |x| (x * 32_767).round }.pack("s<*")
      header = [ "RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16, "data", data.bytesize ]
      header.pack("a4Va4a4VvvVVvva4V") + data
    end

    # Floats in -0.9..0.9. drive overdrives the guitar (0 leaves it clean).
    def samples(notes, seconds, drive: 0)
      size = (seconds * RATE).to_i
      mix = Array.new(size, 0.0)
      guitar = drive.positive? ? Array.new(size, 0.0) : mix
      notes.each do |note|
        first = (note.start * RATE).to_i
        case note.voice
        when :kick then kick(mix, first, note.level)
        when :snare, :hat, :ride then noise_drum(mix, first, note.level, *NOISE_DRUMS.fetch(note.voice))
        else tone(note.voice == :guitar ? guitar : mix, first, note)
        end
      end
      size.times { |i| mix[i] += Math.tanh(guitar[i] * drive) / drive } if drive.positive?
      peak = mix.map(&:abs).max
      peak.zero? ? mix : mix.map { |x| x * 0.9 / peak }
    end

    private

    def tone(buffer, first, note)
      voice = VOICES.fetch(note.voice)
      table = TABLES.fetch(note.voice)
      count = [ (note.length * RATE).to_i, buffer.size - first ].min
      step = 440.0 * 2**((note.pitch - 69) / 12.0) * TABLE_SIZE / RATE
      attack = [ voice.attack * RATE, 1 ].max
      release = [ voice.release * RATE, 1 ].max
      fade = Math.exp(-voice.decay / RATE)
      wobble_step = VIBRATO_HZ * TABLE_SIZE / RATE
      phase = wobble = 0.0
      level = note.level
      count.times do |k|
        gain = level
        gain *= k / attack if k < attack
        gain *= (count - k) / release if count - k < release
        buffer[first + k] += table[phase.to_i & TABLE_MASK] * gain
        if voice.vibrato.zero?
          phase += step
        else
          phase += step * (1 + voice.vibrato * SINE[wobble.to_i & TABLE_MASK])
          wobble += wobble_step
        end
        level *= fade
      end
    end

    # A sine that drops from 120 Hz to 45 Hz as it dies away.
    def kick(buffer, first, level)
      count = [ (0.3 * RATE).to_i, buffer.size - first ].min
      sweep = 75.0
      sweep_fade = Math.exp(-30.0 / RATE)
      fade = Math.exp(-9.0 / RATE)
      phase = 0.0
      count.times do |k|
        buffer[first + k] += Math.sin(phase) * level
        phase += 2 * Math::PI * (45.0 + sweep) / RATE
        sweep *= sweep_fade
        level *= fade
      end
    end

    def noise_drum(buffer, first, level, seconds, decay, body_hz, bright)
      count = [ (seconds * RATE).to_i, buffer.size - first ].min
      fade = Math.exp(-decay / RATE)
      body_step = body_hz ? body_hz * TABLE_SIZE / RATE : 0
      offset = first % RATE
      count.times do |k|
        hiss = NOISE[(offset + k) % RATE]
        hiss -= NOISE[(offset + k + 1) % RATE] if bright # a first difference keeps only the top end
        hiss += SINE[(k * body_step).to_i & TABLE_MASK] if body_hz
        buffer[first + k] += hiss * level
        level *= fade
      end
    end
  end
end
