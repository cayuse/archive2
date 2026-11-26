require "test_helper"
require "tmpdir"

class LibrarySample::ClipLibraryTest < ActiveSupport::TestCase
  CATALOG = Rails.root.join("db/library_sample/clips.json").to_s

  setup { @dir = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@dir) }

  def library(*files)
    files.each { |name| FileUtils.touch(File.join(@dir, "#{name}.mp3")) }
    LibrarySample::ClipLibrary.new(catalog_path: CATALOG, dir: @dir)
  end

  def pick(library, genre:, energy: 0.5, song_id: "a", speech: 0.1)
    library.pick(song_id: song_id, genre: genre, features: { "energy" => energy, "speech" => speech })&.name
  end

  test "with nothing generated there is nothing to pick" do
    assert_nil pick(library, genre: "Rock")
  end

  test "picks a style clip by genre and energy" do
    clips = library("rock-high-1", "rock-low", "blues-high", "jazz-low")
    assert_equal "rock-high-1", pick(clips, genre: "Rock/Pop", energy: 0.8)
    assert_equal "rock-low", pick(clips, genre: "Alternative", energy: 0.2)
    assert_equal "blues-high", pick(clips, genre: "Blues/R&B", energy: 0.2), "the only blues clip, though it is the energetic one"
    assert_includes %w[rock-high-1 blues-high], pick(clips, genre: nil, energy: 0.9), "no genre: any style that has clips"
    assert_includes %w[rock-high-1 blues-high], pick(clips, genre: "Polka", energy: 0.9), "a genre no style covers: the same"
    assert_nil pick(clips, genre: "Country"), "country is a style, but none of its clips are generated yet"
    assert_equal [ 4, 0 ], [ clips.style_clips, clips.song_clips ]
  end

  test "spoken-word songs are left to the composer" do
    clips = library("rock-high-1")
    assert_nil pick(clips, genre: "Audiobook")
    assert_nil pick(clips, genre: "Rock", speech: 0.99)
  end

  test "a clip generated for the song itself wins" do
    clips = library("rock-high-1", "6f0e")
    assert_equal "6f0e", pick(clips, genre: "Rock", song_id: "6f0e")
    assert_equal "6f0e", pick(clips, genre: "Audiobook", song_id: "6f0e")
    assert_equal 1, clips.song_clips
  end

  test "every catalog style is a usable pattern with both energies" do
    styles = JSON.parse(File.read(CATALOG)).fetch("styles")
    styles.each do |style|
      assert_nothing_raised { Regexp.new(style.fetch("genres")) }
      assert_equal %w[high low], style.fetch("clips").map { |c| c.fetch("energy") }.uniq.sort, style["style"]
    end
    names = styles.flat_map { |s| s["clips"].map { |c| c["name"] } }
    assert_equal names.uniq, names
  end
end
