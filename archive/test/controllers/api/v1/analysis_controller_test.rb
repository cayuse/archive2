require "test_helper"

class Api::V1::AnalysisControllerTest < ActionDispatch::IntegrationTest
  MODEL = "test/model".freeze
  DIALS = SongAudioFeature::DIALS.to_h { |d| [ d, 0.5 ] }.freeze

  setup do
    _key, @token = ServiceKey.issue!(name: "test-pc", scope: "analysis")
    @auth = { "Authorization" => "Bearer #{@token}" }
    @old = (1..3).map { |i| analysed("Old #{i}", [ 1.0, i / 10.0, 0.0, 0.0 ]) }
    @fresh = with_audio("Fresh")
  end

  def with_audio(title, **attrs)
    song = Song.create!(title: title, user: users(:admin), processing_status: "completed", **attrs)
    song.audio_file.attach(io: File.open(file_fixture("tagged.mp3")), filename: "#{title}.mp3", content_type: "audio/mpeg")
    song
  end

  def analysed(title, vector)
    song = with_audio(title)
    SongAudioFeature.create!(DIALS.merge(song: song, analysis_model: MODEL, tempo_bpm: 100))
    SongEmbedding.create!(song: song, analysis_model: MODEL, dimensions: vector.size, embedding: vector)
    song
  end

  def result_for(song, **features)
    { song_id: song.id, features: DIALS.merge("tempo_bpm" => 123.4).merge(features.stringify_keys), embedding: [ 0.5, 0.5, 0.5, 0.5 ] }
  end

  def write(path, body) = post("/api/v1/analysis/#{path}", params: body.to_json, headers: @auth.merge("Content-Type" => "application/json"))

  # --- who gets in ---

  test "nothing answers without an analysis key" do
    %w[/api/v1/analysis /api/v1/analysis/status /api/v1/analysis/pending /api/v1/analysis/embeddings].each do |path|
      get path
      assert_response :unauthorized, path
      get path, headers: { "Authorization" => "Bearer wrong" }
      assert_response :unauthorized, path
      get path, headers: api_headers(users(:admin))   # a person's login, even an admin's, is not a key
      assert_response :unauthorized, path
    end
    post "/api/v1/analysis/results", params: { model: MODEL, songs: [ result_for(@fresh) ] }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    assert_nil @fresh.reload.audio_feature
  end

  test "an analysis key opens nothing else, and a revoked key opens nothing" do
    get "/api/v1/songs", headers: @auth
    assert_response :unauthorized
    get "/api/v1/analysis/status", headers: @auth
    assert_response :success
    ServiceKey.find_by!(name: "test-pc").revoke!
    get "/api/v1/analysis/status", headers: @auth
    assert_response :unauthorized
  end

  test "only the digest of a key is stored, and use is recorded" do
    key = ServiceKey.find_by!(name: "test-pc")
    assert_not_includes key.attributes.values.map(&:to_s), @token
    assert_equal Digest::SHA256.hexdigest(@token), key.token_digest
    write "results", model: MODEL, songs: [ result_for(@fresh) ]
    assert_equal 1, key.reload.writes_count
    assert key.last_used_at
  end

  # --- reading ---

  test "the guide describes every route" do
    get "/api/v1/analysis", headers: @auth
    guide = response.parsed_body
    listed = guide["endpoints"].map { |e| [ e["method"], e["path"] ] }
    routes = Rails.application.routes.routes.select { |r| r.defaults[:controller] == "api/v1/analysis" }
                  .map { |r| [ r.verb, r.path.spec.to_s.sub("(.:format)", "") ] }
    assert_equal routes.sort, listed.sort
    assert_equal [ MODEL, 4 ], guide["library"].values_at("analysis_model", "embedding_dimensions")
    assert_equal SongAudioFeature::DIALS.sort, guide.dig("definitions", "dials", "phrases").keys.sort
  end

  test "status and pending tell what is waiting; results take a song off the list" do
    get "/api/v1/analysis/status", headers: @auth
    status = response.parsed_body
    assert_equal [ 3, 1, MODEL, 4 ], status.values_at("songs_analysed", "songs_awaiting_analysis", "analysis_model", "embedding_dimensions")

    get "/api/v1/analysis/pending", headers: @auth
    pending = response.parsed_body["songs"]
    assert_equal [ @fresh.id ], pending.map { |s| s["id"] }
    assert_equal "Fresh", pending.first["title"]

    get URI(pending.first["audio_url"]).path, headers: @auth
    assert_response :success
    assert_equal File.binread(file_fixture("tagged.mp3")), response.body

    write "results", model: MODEL, songs: [ result_for(@fresh) ]
    assert_response :success
    get "/api/v1/analysis/pending", headers: @auth
    assert_empty response.parsed_body["songs"]
  end

  test "songs, features and embeddings page through the library and can be limited to what changed" do
    get "/api/v1/analysis/embeddings", params: { limit: 2 }, headers: @auth
    first = response.parsed_body
    assert_equal 2, first["embeddings"].size
    get "/api/v1/analysis/embeddings", params: { limit: 2, after: first["next_after"] }, headers: @auth
    second = response.parsed_body
    assert_equal 1, second["embeddings"].size
    assert_nil second["next_after"]
    all = first["embeddings"] + second["embeddings"]
    assert_equal @old.map(&:id).sort, all.map { |e| e["song_id"] }.sort
    one = all.find { |e| e["song_id"] == @old.first.id }
    assert_equal [ 1.0, 0.1, 0.0, 0.0 ], Base64.strict_decode64(one["embedding_b64"]).unpack("e*").map { |v| v.round(3) }

    get "/api/v1/analysis/features", params: { ids: @old.first.id }, headers: @auth
    row = response.parsed_body["features"].sole
    assert_equal [ 0.5, 100.0, MODEL ], row.values_at("energy", "tempo_bpm", "analysis_model")

    get "/api/v1/analysis/songs", params: { since: 1.hour.from_now.utc.iso8601 }, headers: @auth
    assert_empty response.parsed_body["songs"]
    get "/api/v1/analysis/songs", params: { ids: [ @fresh.id, @old.first.id ].join(",") }, headers: @auth
    assert_equal({ @fresh.id => false, @old.first.id => true }, response.parsed_body["songs"].to_h { |s| [ s["id"], s["analysed"] ] })

    get "/api/v1/analysis/songs", params: { since: "yesterday" }, headers: @auth
    assert_response :unprocessable_content
  end

  # --- writing ---

  test "results are stored, and can be sent as base64" do
    packed = Base64.strict_encode64([ 0.25, 0.5, 0.75, 1.0 ].pack("e*"))
    write "results", model: MODEL, songs: [ { song_id: @fresh.id, features: DIALS.merge("energy" => 0.91, "loudness_db" => -9.5), embedding_b64: packed } ]
    assert_response :success
    assert_equal({ "songs" => 1 }, response.parsed_body["written"])
    feature = @fresh.reload.audio_feature
    assert_equal [ 0.91, -9.5, MODEL ], [ feature.energy, feature.loudness_db, feature.analysis_model ]
    assert_equal [ 0.25, 0.5, 0.75, 1.0 ], SongEmbedding.find_by!(song: @fresh).embedding
    assert_not_includes Song.awaiting_analysis, @fresh
  end

  test "a request with anything wrong in it writes nothing at all" do
    other = with_audio("Other")
    bad = {
      "another model" => { model: "some/other-model", songs: [ result_for(@fresh) ] },
      "a dial out of range" => { model: MODEL, songs: [ result_for(other), result_for(@fresh, energy: 1.7) ] },
      "a missing dial" => { model: MODEL, songs: [ result_for(@fresh).tap { |r| r[:features] = r[:features].except("speech") } ] },
      "not a number" => { model: MODEL, songs: [ result_for(@fresh, tempo_bpm: "fast") ] },
      "wrong vector size" => { model: MODEL, songs: [ result_for(@fresh).merge(embedding: [ 0.1, 0.2 ]) ] },
      "a vector of zeros" => { model: MODEL, songs: [ result_for(@fresh).merge(embedding: [ 0, 0, 0, 0 ]) ] },
      "an unknown song" => { model: MODEL, songs: [ result_for(other), { song_id: SecureRandom.uuid, features: DIALS, embedding: [ 1, 0, 0, 0 ] } ] },
      "a song with no audio" => { model: MODEL, songs: [ result_for(songs(:one)) ] },
      "the same song twice" => { model: MODEL, songs: [ result_for(@fresh), result_for(@fresh) ] },
      "no songs" => { model: MODEL, songs: [] }
    }
    bad.each do |what, body|
      assert_no_difference [ "SongAudioFeature.count", "SongEmbedding.count" ], what do
        write "results", body
      end
      assert_response :unprocessable_content, what
      assert response.parsed_body["problems"].any?, what
    end
    post "/api/v1/analysis/results", params: "{not json", headers: @auth.merge("Content-Type" => "application/json")
    assert_response :unprocessable_content
  end

  test "an analysed song is not overwritten unless replace is asked for" do
    write "results", model: MODEL, songs: [ result_for(@old.first, energy: 0.01) ]
    assert_response :unprocessable_content
    assert_match "already analysed", response.parsed_body["problems"].first
    assert_equal 0.5, @old.first.audio_feature.reload.energy

    write "results", model: MODEL, replace: true, songs: [ result_for(@old.first, energy: 0.01) ]
    assert_response :success
    assert_equal 0.01, @old.first.audio_feature.reload.energy
    assert_equal 3, SongEmbedding.count
  end

  test "a neighbour list replaces that song's list and leaves the others alone" do
    a, b, c = @old
    SongNeighbor.create!(song: a, neighbor: c, rank: 0, score: 0.5)
    SongNeighbor.create!(song: b, neighbor: c, rank: 0, score: 0.6)
    write "neighbors", lists: [ { song_id: a.id, neighbors: [ { id: b.id, score: 0.9 }, { id: c.id, score: 0.8 } ] } ]
    assert_response :success
    assert_equal({ "lists" => 1, "links" => 2 }, response.parsed_body["written"])
    assert_equal [ [ b.id, 0, 0.9 ], [ c.id, 1, 0.8 ] ], SongNeighbor.where(song: a).order(:rank).pluck(:neighbor_id, :rank, :score)
    assert_equal 1, SongNeighbor.where(song: b).count

    get "/api/v1/analysis/neighbors", params: { ids: a.id }, headers: @auth
    assert_equal [ b.id, c.id ], response.parsed_body["lists"].sole["neighbors"].map { |n| n["id"] }
  end

  test "neighbour lists that break the rules write nothing" do
    a, b, c = @old
    bad = {
      "itself" => [ { id: a.id, score: 1.0 } ],
      "a repeat" => [ { id: b.id, score: 0.9 }, { id: b.id, score: 0.8 } ],
      "an unanalysed song" => [ { id: @fresh.id, score: 0.9 } ],
      "worst first" => [ { id: b.id, score: 0.2 }, { id: c.id, score: 0.9 } ],
      "a score that is no similarity" => [ { id: b.id, score: 42 } ],
      "none" => [],
      "too many" => Array.new(51) { { id: b.id, score: 0.5 } }
    }
    bad.each do |what, neighbors|
      assert_no_difference "SongNeighbor.count", what do
        write "neighbors", lists: [ { song_id: a.id, neighbors: neighbors } ]
      end
      assert_response :unprocessable_content, what
    end
    write "neighbors", lists: [ { song_id: @fresh.id, neighbors: [ { id: a.id, score: 0.9 } ] } ]
    assert_response :unprocessable_content
  end

  test "genre affinities are replaced whole, and cannot be wiped by a partial list" do
    one, two = genres(:one), genres(:two)
    three, four = Genre.create!(name: "Third"), Genre.create!(name: "Fourth")
    write "genre_affinities", affinities: [ [ one, two ], [ two, one ], [ one, three ], [ three, four ] ].map { |g, r| { genre_id: g.id, related_genre_id: r.id, score: 1.5 } }
    assert_response :success
    assert_equal 4, GenreAffinity.count

    write "genre_affinities", affinities: [ { genre_id: one.id, related_genre_id: two.id, score: 2.0 } ]
    assert_response :unprocessable_content
    assert_match "WHOLE table", response.parsed_body["problems"].first
    assert_equal 4, GenreAffinity.count

    write "genre_affinities", affinities: [ { genre_id: one.id, related_genre_id: one.id, score: 2.0 } ], allow_shrink: true
    assert_response :unprocessable_content
    assert_equal 4, GenreAffinity.count

    write "genre_affinities", affinities: [ { genre_id: one.id, related_genre_id: two.id, score: 2.0 } ], allow_shrink: true
    assert_response :success
    assert_equal [ [ one.id, two.id, 2.0 ] ], GenreAffinity.pluck(:genre_id, :related_genre_id, :score)
    get "/api/v1/analysis/genres", headers: @auth
    assert_includes response.parsed_body["genres"].map { |g| g["name"] }, "Third"
  end
end
