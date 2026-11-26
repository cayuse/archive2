require "digest"
require "json"

module LibrarySample
  # AI-generated songs on disk (db/library_sample/clips, see GENERATING_SONGS.md there), in two forms:
  #
  #   <song id>.mp3   a song generated for one particular song, from song_prompts.jsonl
  #   <name>.mp3      a style clip from clips.json: a few made-up songs per style, each in an
  #                   energetic and a mellow version, shared by every song of that style
  #
  # pick gives a song its own clip if there is one, else a style clip by genre and measured
  # energy. Only files actually on disk count, so with nothing generated every pick is nil and
  # AudioSynth composes the music itself.
  class ClipLibrary
    Clip = Struct.new(:name, :path, :style, :energy, :bpm) # bpm nil: made for the song, leave its tempo alone
    def initialize(catalog_path:, dir:)
      @dir = dir
      # [genre pattern, the clips of that style that are on disk], for every style in the catalog
      @styles = JSON.parse(File.read(catalog_path)).fetch("styles").map do |style|
        clips = style.fetch("clips").filter_map do |clip|
          path = File.join(dir, "#{clip.fetch('name')}.mp3")
          Clip.new(clip.fetch("name"), path, style.fetch("style"), clip.fetch("energy"), clip.fetch("bpm")) if File.exist?(path)
        end
        [ Regexp.new(style.fetch("genres"), Regexp::IGNORECASE), clips ]
      end
    end

    def style_clips
      @styles.sum { |_pattern, clips| clips.size }
    end

    def song_clips
      Dir.glob(File.join(@dir, "*.mp3")).size - style_clips
    end

    # features: a song_audio_features row as a hash, or nil. Returns a Clip or nil.
    def pick(song_id:, genre:, features:)
      own = File.join(@dir, "#{song_id}.mp3")
      return Clip.new(song_id, own, nil, nil, nil) if File.exist?(own)
      # The style clips are all music, so spoken-word tracks are left to the composer.
      return if Arrangement.spoken?(genre, features)
      number = Digest::MD5.hexdigest(song_id.to_s).to_i(16)
      clips = style_clips_for(genre, number)
      return if clips.empty?
      wanted = (features&.dig("energy") || 0.5) >= 0.5 ? "high" : "low"
      matching = clips.select { |clip| clip.energy == wanted }
      matching = clips if matching.empty?
      matching[number % matching.size]
    end

    private

    # First matching style wins ("Blues/R&B" is blues). A genre whose style has no clips yet gets
    # none, so those songs are composed; only a song whose genre fits no style at all (or that
    # has no genre) borrows from whichever styles do have clips.
    def style_clips_for(genre, number)
      _pattern, clips = @styles.find { |pattern, _clips| genre.to_s.match?(pattern) }
      return clips if clips
      generated = @styles.map(&:last).reject(&:empty?)
      generated.empty? ? [] : generated[number % generated.size]
    end
  end
end
