# Development seed: 25 generated songs across 10 genres, playlists, and one jukebox.
# Run after db:seed (needs the admin user):  bin/rails runner db/dev_seeds.rb
# Audio is synthesized with ffmpeg (sine tones), so nothing here is copyrighted.
require "open3"
require "tmpdir"

GENRES = {
  "Rock"       => "#C0392B", "Jazz"      => "#2980B9", "Classical" => "#8E44AD",
  "Hip Hop"    => "#F39C12", "Country"   => "#D35400", "Electronic" => "#16A085",
  "Blues"      => "#34495E", "Reggae"    => "#27AE60", "Folk"      => "#7F8C8D",
  "Pop"        => "#E91E63"
}.freeze

# [title, artist, album, genre]
TRACKS = [
  [ "Granite Road",        "The Test Tones",    "Signal Check",     "Rock" ],
  [ "Overdrive Sunday",    "The Test Tones",    "Signal Check",     "Rock" ],
  [ "Feedback Loop",       "Null Pointer",      "Segfault",         "Rock" ],
  [ "Blue Fixture",        "Fixture Quartet",   "After Hours",      "Jazz" ],
  [ "Seven Over Four",     "Fixture Quartet",   "After Hours",      "Jazz" ],
  [ "Walking Stub",        "Mock Trio",         "Standards",        "Jazz" ],
  [ "Sonata in A 440",     "Sine Philharmonic", "Pure Tones",       "Classical" ],
  [ "Etude for Oscillator", "Sine Philharmonic", "Pure Tones",      "Classical" ],
  [ "Adagio for Harness",  "Sine Philharmonic", "Pure Tones",       "Classical" ],
  [ "Stack Trace",         "MC Assert",         "Green Build",      "Hip Hop" ],
  [ "Push to Main",        "MC Assert",         "Green Build",      "Hip Hop" ],
  [ "Dusty Schema",        "The Migrations",    "Rollback Road",    "Country" ],
  [ "Long Way to Prod",    "The Migrations",    "Rollback Road",    "Country" ],
  [ "Square Wave City",    "Voltage Kids",      "Hertz",            "Electronic" ],
  [ "Low Pass",            "Voltage Kids",      "Hertz",            "Electronic" ],
  [ "Sidechain",           "Voltage Kids",      "Hertz",            "Electronic" ],
  [ "Flaky Test Blues",    "Slow Query Sam",    "Timeout",          "Blues" ],
  [ "Deadlock Morning",    "Slow Query Sam",    "Timeout",          "Blues" ],
  [ "One Drop Queue",      "Island Fixtures",   "Steady State",     "Reggae" ],
  [ "Easy Skanking Seed",  "Island Fixtures",   "Steady State",     "Reggae" ],
  [ "Paper Lanterns",      "Mabel Stubbs",      "Kitchen Tapes",    "Folk" ],
  [ "River Under Ice",     "Mabel Stubbs",      "Kitchen Tapes",    "Folk" ],
  [ "Sugar Rush",          "Factory Girl",      "Bright Defaults",  "Pop" ],
  [ "Hold the Line Item",  "Factory Girl",      "Bright Defaults",  "Pop" ],
  [ "Last Song Tonight",   "Factory Girl",      "Bright Defaults",  "Pop" ]
].freeze

admin = User.find_by!(email: "admin@musicarchive.com")
genres = GENRES.to_h { |name, color| [ name, Genre.find_or_create_by!(name: name) { |g| g.color = color } ] }
track_no = Hash.new(0)

Dir.mktmpdir do |dir|
  TRACKS.each_with_index do |(title, artist_name, album_title, genre_name), i|
    next if Song.exists?(title: title)

    seconds = 20 + (i % 5) * 5 # 20..40s: short enough to watch tracks advance
    freq    = (220 * 2**(i / 12.0)).round # one semitone per track, so each is audibly distinct
    file    = File.join(dir, format("%02d.mp3", i + 1))
    _, err, status = Open3.capture3(
      "ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi",
      "-i", "sine=frequency=#{freq}:duration=#{seconds}",
      "-af", "tremolo=f=#{2 + i % 4}:d=0.6,volume=0.4",
      "-metadata", "title=#{title}", "-metadata", "artist=#{artist_name}",
      "-metadata", "album=#{album_title}", "-metadata", "genre=#{genre_name}",
      "-b:a", "128k", file
    )
    raise "ffmpeg failed for #{title}: #{err}" unless status.success?

    artist = Artist.find_or_create_by!(name: artist_name)
    album  = Album.find_or_create_by!(title: album_title, artist: artist)
    song = Song.new(
      title: title, artist: artist, album: album, genre: genres.fetch(genre_name), user: admin,
      track_number: (track_no[album_title] += 1), duration: seconds, file_format: "mp3",
      file_size: File.size(file), processing_status: "completed",
      original_filename: "#{title}.mp3"
    )
    song.audio_file.attach(io: File.open(file), filename: "#{title}.mp3", content_type: "audio/mpeg")
    song.save!
  end
end

def fill(playlist, songs)
  songs.each_with_index do |song, i|
    next if PlaylistsSong.exists?(playlist_id: playlist.id, song_id: song.id)
    PlaylistsSong.create!(playlist_id: playlist.id, song_id: song.id, position: i + 1)
  end
end

everything = Playlist.find_or_create_by!(name: "Everything", user: admin)
upbeat     = Playlist.find_or_create_by!(name: "Upbeat", user: admin)
mellow     = Playlist.find_or_create_by!(name: "Mellow", user: admin)
seeded     = Song.where(title: TRACKS.map(&:first)).order(:created_at)
fill(everything, seeded)
fill(upbeat, seeded.joins(:genre).where(genres: { name: [ "Rock", "Hip Hop", "Electronic", "Pop", "Reggae" ] }))
fill(mellow, seeded.joins(:genre).where(genres: { name: [ "Jazz", "Classical", "Blues", "Folk", "Country" ] }))

jukebox = Jukebox.find_or_initialize_by(session_id: "dev-party")
jukebox.update!(name: "Dev Party", owner: admin, guest_password: "guest", admin_password: "boss", status: "active")
[ everything, upbeat ].each do |playlist|
  JukeboxPlaylistAssignment.find_or_create_by!(jukebox: jukebox, playlist: playlist)
end

puts "songs=#{Song.count} with_audio=#{Song.joins(:audio_file_attachment).count} genres=#{Genre.count} " \
     "artists=#{Artist.count} albums=#{Album.count} playlists=#{Playlist.count} jukebox=#{jukebox.id}"
