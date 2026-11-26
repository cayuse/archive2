# Local additions to a restored copy of the production database, so the live
# test stack is usable without knowing anyone's real password:
# a local admin login and a jukebox it owns. Idempotent.
# Run by bin/docker-live:  bin/rails runner db/live_seeds.rb

user = User.find_or_initialize_by(email: "live-test@example.test")
user.update!(name: "Live Test", password: "admin123", password_confirmation: "admin123", role: "admin")

jukebox = Jukebox.find_or_initialize_by(session_id: "live-test")
jukebox.update!(name: "Live Test", owner: user, guest_password: "guest", admin_password: "boss", status: "active")

# Feed it from the three largest real playlists.
largest = Playlist.joins(:playlists_songs).group("playlists.id").order(Arel.sql("COUNT(*) DESC")).limit(3)
largest.each { |playlist| JukeboxPlaylistAssignment.find_or_create_by!(jukebox: jukebox, playlist: playlist) }

missing = Song.joins(:audio_file_attachment).limit(200).count { |song| !song.audio_file.blob.service.exist?(song.audio_file.key) }
puts "live: songs=#{Song.count} playlists=#{jukebox.playlists.pluck(:name).join(', ')} jukebox=#{jukebox.id}"
puts "live: #{missing} of the first 200 songs have no audio file under storage/ " \
     "(check ARCHIVE_LIVE_STORAGE if this is not 0)"
