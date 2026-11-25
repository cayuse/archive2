# A realistic slice of the real library for development and test databases.
#
#   export  run against a full library (the production clone), writes the fixture:
#             DATABASE_URL=postgres://.../archive_prod_clone bin/rails 'library:sample_export[600]'
#   seed    run against a development database, loads the fixture and gives every song audio:
#             bin/rails library:sample_seed            (LIMIT=100 for a smaller, still varied, set;
#                                                       REFRESH_AUDIO=1 to make all audio again)
#           Audio comes from AI-generated clips in db/library_sample/clips/ when they are there
#           (db/library_sample/GENERATING_SONGS.md says how to make them), else it is composed.
#   prompts rewrites db/library_sample/song_prompts.jsonl from the fixture (after a new export):
#             bin/rails library:sample_prompts
namespace :library do
  sample_dir = Rails.root.join("db/library_sample")
  sample_fixture = sample_dir.join("library_sample.json.gz")

  desc "Write a varied slice of this database's library to db/library_sample (read-only on the database)"
  task :sample_export, [ :count ] => :environment do |_t, args|
    LibrarySample::Exporter.new(count: (args[:count] || 600).to_i, path: sample_fixture.to_s).call
  end

  desc "Write one AI music prompt per sample song to db/library_sample/song_prompts.jsonl"
  task sample_prompts: :environment do
    LibrarySample::PromptWriter.new(fixture_path: sample_fixture.to_s, path: sample_dir.join("song_prompts.jsonl").to_s).call
  end

  desc "Load the library sample into this database with stand-in audio (rerunnable). LIMIT=n, REFRESH_AUDIO=1."
  task sample_seed: :environment do
    abort "library:sample_seed is for development and test databases" if Rails.env.production?
    user = User.find_by(email: "admin@musicarchive.com") || User.order(:created_at).first
    puts "no users yet: songs will have no owner and no playlists are made (run db:seed first)" unless user
    clips_dir = ENV["SAMPLE_CLIPS_DIR"].presence || sample_dir.join("clips").to_s
    clips = LibrarySample::ClipLibrary.new(catalog_path: sample_dir.join("clips.json").to_s, dir: clips_dir)
    puts "generated clips on disk: #{clips.song_clips} per-song, #{clips.style_clips} per-style; everything else is composed"
    LibrarySample::Seeder.new(path: sample_fixture.to_s, user: user, clips: clips, limit: ENV["LIMIT"]&.to_i,
                              refresh_audio: ENV["REFRESH_AUDIO"].present?).call
  end
end
