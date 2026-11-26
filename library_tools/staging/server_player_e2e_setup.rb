u = User.find_by!(email: "station-test@example.invalid")
n = ArchiveNode.current
n.update!(local_playback: true)
n.regenerate_player_token if n.player_token.blank?
n.users << u unless u.can_play_on?(n)
Jukebox.where(server_playback: true).find_each(&:end_server_playback!)
Jukebox.where(owner: u, session_id: %w[e2e-party e2e-other]).destroy_all
a = Jukebox.create!(owner: u, name: "E2E Party", session_id: "e2e-party", guest_password: "e2eguest", admin_password: "e2eadmin", fill_mode: "radio")
b = Jukebox.create!(owner: u, name: "E2E Other", session_id: "e2e-other", guest_password: "e2eguest", fill_mode: "radio")
song = Song.joins(:audio_feature).where("songs.duration > 200").first
puts "TOKEN=#{n.player_token}"
puts "PARTY=#{a.id}"
puts "OTHER=#{b.id}"
puts "SONG=#{song.id}"
puts "ROLE=#{u.role}"
