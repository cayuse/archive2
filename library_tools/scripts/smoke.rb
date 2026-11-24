# Smoke test: render the main library pages against staging, with login bypassed in this process only.
# Run:  bash rails.sh bundle exec rails runner /work/scripts/smoke.rb
user = User.where(role: "admin").first || User.first
ApplicationController.class_eval do
  define_method(:authenticate_user!) { true }
  define_method(:current_user) { user }
end

Api::V1::SongsController.class_eval do
  define_method(:authenticate_encrypted_token_user!) { @current_api_user = user }
  # development mode raises on callbacks that name actions the controller does not define (existing issue)
  %i[bulk_create bulk_update bulk_upload direct_upload create_from_blob].each { |a| define_method(a) {} unless method_defined?(a) }

end

s = ActionDispatch::Integration::Session.new(Rails.application)
s.host! "localhost"

feat = Song.where("artist_credit ilike '%feat.%'").first
multi = Album.where("disc_total > 1").joins(:songs).first
guest = Artist.joins(:song_artist_credits).where.not(id: Song.select(:artist_id).where.not(artist_id: nil)).first
seed = Song.find("0d46d39f-07a5-448e-ae06-bce2257ff50f") # Whole Lotta Love (analysed)
unanalysed = Song.where.not(id: SongAudioFeature.select(:song_id)).first
paths = {
  "radio page" => "/songs/#{seed.id}/radio",
  "radio page (steered)" => "/songs/#{seed.id}/radio?energy=-0.6",
  "radio page (not analysed)" => "/songs/#{unanalysed.id}/radio",
  "radio API" => "/api/v1/songs/#{seed.id}/radio?count=5&energy=0.5",
  "songs index" => "/songs",
  "songs search" => "/songs?q=greatest",
  "song show (featured)" => "/songs/#{feat.id}",
  "albums index" => "/albums",
  "album show (multi-disc)" => "/albums/#{multi.id}",
  "artists index" => "/artists",
  "artist show (main)" => "/artists/#{feat.artist_id}",
  "artist show (features only)" => "/artists/#{guest.id}",
  "genres index" => "/genres",
  "playlists index" => "/playlists"
}
fail = 0
paths.each do |label, path|
  begin
    code = s.get(path)
    body = s.response.body
    note = ""
    note = " credit shown=#{body.include?(ERB::Util.html_escape(feat.artist_credit))}" if label.start_with?("song show")
    note = " songs listed=#{body.scan('data-song-id').size}" if label.start_with?("artist show", "album show", "radio page")
    note = " -> " + JSON.parse(body)["songs"].map { |x| x["artist"] }.join(" | ")[0, 110] if label == "radio API"
    puts format("%-30s %s %7d bytes%s", label, code, body.size, note)
    if code >= 400
      fail += 1
      puts body[/<h1.*?<\/h1>/m].to_s[0, 300], body[/<div class="exception-message".*?<\/div>/m].to_s[0, 600]
    end
  rescue => e
    fail += 1
    puts format("%-30s EXCEPTION %s: %s", label, e.class, e.message[0, 300])
  end
end
puts "guest artist: #{guest.name}, main songs=#{guest.songs.count}, all_songs=#{guest.all_songs.count}"
puts fail.zero? ? "ALL OK" : "#{fail} FAILED"
