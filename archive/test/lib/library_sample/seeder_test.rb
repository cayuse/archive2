require "test_helper"
require "securerandom"
require "tmpdir"
require "zlib"

class LibrarySample::SeederTest < ActiveSupport::TestCase
  # Stands in for ffmpeg: writes a few bytes where the audio would go.
  class FakeSynth
    def render(path:, **)
      File.write(path, "not really audio")
      path
    end
  end

  setup do
    @now = Time.current.iso8601
    @rock, @polka, @artist, @album, @first, @second = Array.new(6) { SecureRandom.uuid }
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "sample.json.gz")
    Zlib::GzipWriter.open(@path) { |gz| gz.write(JSON.generate(fixture)) }
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "loads songs with their analysis, audio and links" do
    seed

    first = Song.find(@first)
    assert_equal genres(:one), first.genre, "Rock already existed under another id, so the song points at that one"
    assert_equal "Polka", Song.find(@second).genre.name
    assert_equal users(:admin), first.user
    assert_equal 28, first.duration, "the length of the synthesized clip, not of the real recording"
    assert first.audio_file.attached?
    assert_equal first.audio_file.blob.key, first.file_tag.blob_key
    assert_equal 0.9, first.audio_feature.energy
    assert_equal [ Song.find(@second) ], first.similar_songs.to_a
    assert_equal [ genres(:one).id ], GenreAffinity.where(genre_id: Genre.find_by!(name: "Polka").id).pluck(:related_genre_id)
    assert_includes Playlist.find_by!(name: "Sample: High Energy", user: users(:admin)).songs, first
  end

  test "running it again changes nothing" do
    seed
    assert_no_difference [ "Song.count", "ActiveStorage::Blob.count", "SongNeighbor.count", "PlaylistsSong.count", "Genre.count" ] do
      seed
    end
  end

  test "refreshing replaces the audio and nothing else" do
    seed
    old_key = Song.find(@first).audio_file.blob.key
    assert_no_difference [ "Song.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
      seed(refresh_audio: true)
    end
    assert_not_equal old_key, Song.find(@first).audio_file.blob.key
    assert_equal Song.find(@first).audio_file.blob.key, Song.find(@first).file_tag.blob_key
  end

  test "a limit loads only the first songs and the rows that belong to them" do
    seed(limit: 1)
    assert Song.exists?(@first)
    assert_not Song.exists?(@second)
    assert_empty SongNeighbor.where(song_id: @first), "the only neighbour was left out"
  end

  private

  def seed(limit: nil, refresh_audio: false)
    clips = LibrarySample::ClipLibrary.new(catalog_path: Rails.root.join("db/library_sample/clips.json").to_s, dir: @dir)
    LibrarySample::Seeder.new(path: @path, user: users(:admin), clips: clips, limit: limit, refresh_audio: refresh_audio,
                               synth: FakeSynth.new, out: StringIO.new).call
  end

  def stamps
    { "created_at" => @now, "updated_at" => @now }
  end

  def song(id, title, genre_id, track)
    { "id" => id, "title" => title, "album_id" => @album, "artist_id" => @artist, "genre_id" => genre_id,
      "track_number" => track, "duration" => 224, "file_format" => "mp3", "file_size" => 5_000_000,
      "processing_status" => "completed", "original_filename" => "#{title}.mp3" }.merge(stamps)
  end

  def feature(song_id, energy)
    { "id" => SecureRandom.uuid, "song_id" => song_id, "tempo_bpm" => 120.0, "energy" => energy,
      "danceability" => 0.5, "acousticness" => 0.5, "speech" => 0.1 }.merge(stamps)
  end

  def fixture
    {
      "genres" => [ { "id" => @rock, "name" => "Rock" }.merge(stamps), { "id" => @polka, "name" => "Polka" }.merge(stamps) ],
      "artists" => [ { "id" => @artist, "name" => "Sample Artist" }.merge(stamps) ],
      "albums" => [ { "id" => @album, "title" => "Sample Album", "artist_id" => @artist }.merge(stamps) ],
      "songs" => [ song(@first, "First", @rock, 1), song(@second, "Second", @polka, 2) ],
      "song_artist_credits" => [ { "id" => SecureRandom.uuid, "song_id" => @first, "artist_id" => @artist, "position" => 0 }.merge(stamps) ],
      "song_file_tags" => [ { "id" => SecureRandom.uuid, "song_id" => @first, "title" => "First", "duration_seconds" => 224.3 }.merge(stamps) ],
      "song_audio_features" => [ feature(@first, 0.9), feature(@second, 0.2) ],
      "song_embeddings" => [ { "id" => SecureRandom.uuid, "song_id" => @first, "dimensions" => 2, "embedding" => [ 0.6, 0.8 ] }.merge(stamps) ],
      "song_neighbors" => [ { "id" => SecureRandom.uuid, "song_id" => @first, "neighbor_id" => @second, "rank" => 0, "score" => 0.9 }.merge(stamps) ],
      "genre_affinities" => [ { "id" => SecureRandom.uuid, "genre_id" => @polka, "related_genre_id" => @rock, "score" => 2.0 }.merge(stamps) ]
    }
  end
end
