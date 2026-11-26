# A jukebox for browser_player_e2e.mjs: owned by the staging test user, filled from a playlist of
# songs whose audio files exist on staging (the Drop Box imports; the rest of the copied library
# has database rows but no files).
u = User.find_by!(email: "station-test@example.invalid")
ids = Song.joins(:audio_file_attachment).order(created_at: :desc).limit(400).select { |s| ActiveStorage::Blob.service.exist?(s.audio_file.key) }.map(&:id)
abort "no songs with audio files on staging: drop some into the Drop Box first" if ids.size < 4
playlist = Playlist.find_or_create_by!(user: u, name: "Browser E2E")
playlist.playlists_songs.delete_all
ids[0...-1].each_with_index { |id, i| PlaylistsSong.create!(playlist: playlist, song_id: id, position: i + 1) }
Jukebox.where(owner: u, session_id: "browser-e2e").destroy_all
j = Jukebox.create!(owner: u, name: "Browser E2E", session_id: "browser-e2e", guest_password: "e2eguest", fill_mode: "random")
j.jukebox_playlist_assignments.create!(playlist: playlist, enabled: true, weight: 1)
puts "JUKEBOX=#{j.id}"
puts "SONGS=#{ids.size}"
# a song with audio that is NOT on the playlist, for the test to request mid-song
puts "REQUEST_SONG=#{ids.last}"
