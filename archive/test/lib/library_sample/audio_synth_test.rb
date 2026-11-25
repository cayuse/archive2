require "test_helper"
require "tmpdir"

class LibrarySample::AudioSynthTest < ActiveSupport::TestCase
  def arrange(features = {}, genre: "Rock", seconds: 20, song_id: "a")
    LibrarySample::Arrangement.new(song_id: song_id, seconds: seconds, features: features, genre: genre)
  end

  def starts(arrangement, voice)
    arrangement.notes.select { |n| n.voice == voice }.map(&:start)
  end

  test "the beat follows the measured tempo" do
    kicks = starts(arrange({ "tempo_bpm" => 120.0, "danceability" => 0.9 }, genre: "Techno & Trance"), :kick)
    assert_in_delta 0.5, kicks[3] - kicks[2], 0.001, "four on the floor at 120 bpm is a kick every half second"
    assert_equal 150.0, arrange({ "tempo_bpm" => 150.0 }).bpm
    assert_equal 117.0, arrange({ "tempo_bpm" => 234.0 }).bpm, "a double-time reading is folded back"
  end

  test "genre picks the style and the dials fill in when there is no genre" do
    { "Jazz" => :jazz, "Blues/R&B" => :blues, "Rock/Pop" => :rock, "Hip Hop/Rap" => :electronic,
      "Country & Folk" => :acoustic, "Reggae" => :reggae, "Classical" => :classical, "Audiobook" => :spoken }.each do |genre, style|
      assert_equal style, arrange(genre: genre).style, genre
    end
    assert_equal :electronic, arrange({ "electronic" => 0.9 }, genre: nil).style
    assert_equal :classical, arrange({ "acousticness" => 0.9, "energy" => 0.1 }, genre: nil).style
    assert_equal :spoken, arrange({ "speech" => 0.97 }, genre: "Rock").style
    assert_equal :rock, arrange({ "speech" => 0.9 }, genre: "Rock").style, "a high percentile is not yet talking"
  end

  test "styles differ in what plays" do
    assert_empty starts(arrange(genre: "Classical"), :kick)
    assert_empty arrange(genre: "Audiobook").notes.map(&:voice).uniq - [ :voice ]
    assert_not_empty starts(arrange(genre: "Jazz"), :ride)
    assert_equal :voice, arrange({ "instrumental" => 0.1 }).notes.last.voice
    assert_includes arrange({ "instrumental" => 0.9 }).notes.map(&:voice), :guitar
  end

  test "a song always gets the same tune and another song a different one" do
    pitches = ->(a) { a.notes.map { |n| [ n.start, n.pitch, n.voice ] } }
    assert_equal pitches.call(arrange), pitches.call(arrange)
    assert_not_equal pitches.call(arrange), pitches.call(arrange(song_id: "b"))
  end

  test "an unanalysed song still gets music" do
    assert_not_empty arrange(nil, genre: nil).notes
  end

  test "clip length follows the real length within bounds" do
    assert_equal 15, LibrarySample::AudioSynth.clip_seconds(nil)
    assert_equal 28, LibrarySample::AudioSynth.clip_seconds(224)
    assert_equal 30, LibrarySample::AudioSynth.clip_seconds(3600)
  end

  test "the synth plays an arrangement at a sane level" do
    arrangement = arrange({ "aggression" => 0.9 }, seconds: 4)
    samples = LibrarySample::Synth.new.samples(arrangement.notes, 4, drive: arrangement.drive)
    assert_equal 4 * LibrarySample::Synth::RATE, samples.size
    assert_in_delta 0.9, samples.map(&:abs).max, 0.001
  end

  test "renders a playable file in each format" do
    skip "ffmpeg not installed" unless system("ffmpeg -version > /dev/null 2>&1")
    Dir.mktmpdir do |dir|
      LibrarySample::AudioSynth::FORMATS.each_key do |format|
        path = LibrarySample::AudioSynth.new.render(
          path: File.join(dir, "clip.#{format}"), song_id: "a", file_format: format, seconds: 3,
          features: { "tempo_bpm" => 128.0, "energy" => 0.9 }, tags: { "title" => "It's a: test, song", "genre" => "Rock" }
        )
        seconds = `ffprobe -v error -show_entries format=duration -of csv=p=0 #{path}`.to_f
        assert_in_delta 3.0, seconds, 0.2, format
        assert_empty Dir.glob(File.join(dir, "*.wav")), "the intermediate file is cleaned up"
      end
    end
  end

  test "a generated clip is cut to length and re-encoded instead of composing" do
    skip "ffmpeg not installed" unless system("ffmpeg -version > /dev/null 2>&1")
    synth = LibrarySample::AudioSynth.new
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.mp3")
      system("ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=8", source, exception: true)
      clip = LibrarySample::ClipLibrary::Clip.new("rock-high-1", source, "rock", "high", 120)
      path = synth.render(path: File.join(dir, "song.m4a"), song_id: "a", file_format: "m4a", seconds: 4,
                          features: { "tempo_bpm" => 126.0 }, tags: { "title" => "T" }, clip: clip)
      assert_in_delta 4.0, `ffprobe -v error -show_entries format=duration -of csv=p=0 #{path}`.to_f, 0.2
      assert_includes synth.clip_filters(clip, { "tempo_bpm" => 126.0 }, 4), "atempo=1.05"
      assert_not_includes synth.clip_filters(clip, { "tempo_bpm" => 90.0 }, 4), "atempo", "too far to stretch"
    end
  end
end
