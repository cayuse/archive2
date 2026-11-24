# Test the jukebox radio auto-fill on staging. Everything is rolled back at the end.
# Run:  bash rails.sh bundle exec rails runner /work/scripts/jukebox_radio_test.rb
seed = Song.find("0d46d39f-07a5-448e-ae06-bce2257ff50f") # Whole Lotta Love
ActiveRecord::Base.transaction do
  jb = Jukebox.first or abort "no jukebox in staging"
  jb.ajb_queue_items.delete_all
  jb.jukebox_playlist_assignments.delete_all
  jb.update!(fill_mode: "radio", min_queue_length: 6, queue_refill_level: 8)
  jb.ajb_queue_items.create!(song: seed, source: "requested")

  c = Api::V1::JukeboxesController.new
  c.instance_variable_set(:@jukebox, jb)
  c.send(:ensure_min_queue_length!)
  puts "jukebox #{jb.name.inspect}, no playlists assigned (whole library):"
  jb.ajb_queue_items.queue_order.includes(song: [ :artist, :genre ]).each do |q|
    puts format("  %-9s %s - %s [%s]", q.source, q.song.artist_display, q.song.title, q.song.genre&.name)
  end

  # with a playlist assigned: picks must come from it
  analysed = SongAudioFeature.limit(300).pluck(:song_id)
  pl = Playlist.create!(name: "radio test #{SecureRandom.hex(3)}", user: jb.owner)
  analysed.each_with_index { |id, i| PlaylistsSong.create!(playlist_id: pl.id, song_id: id, position: i + 1) }
  jb.jukebox_playlist_assignments.create!(playlist: pl, enabled: true)
  jb.ajb_queue_items.where(source: "random").delete_all
  c.send(:ensure_min_queue_length!)
  ids = jb.ajb_queue_items.where(source: "random").pluck(:song_id)
  puts "with a 300-song playlist assigned: #{ids.size} filled, all inside the playlist: #{(ids - analysed).empty?}"
  raise ActiveRecord::Rollback
end
puts "rolled back; fill_mode now #{Jukebox.first.fill_mode.inspect}"
