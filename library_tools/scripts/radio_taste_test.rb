# Show what the genre modes do on staging (read-only).
# Run:  bash rails.sh bundle exec rails runner /work/scripts/radio_taste_test.rb
def line(s) = format("  %-62.62s [%s]", "#{s.artist_display} - #{s.title}", s.genre&.name)

country = Genre.find_by(name: "Country")
seed = Song.joins(:audio_feature, :artist).where(genre: country).where(artists: { name: "George Strait" }).first ||
       Song.joins(:audio_feature).where(genre: country).first
puts "SEED #{line(seed).strip}"
puts "Country is adjacent to: " + GenreAffinity.where(genre: country).order(score: :desc).includes(:related_genre).map { |a| "#{a.related_genre.name} (#{a.score.round(1)}x)" }.join(", ")

%w[any adjacent strict].each do |mode|
  songs = SongRadio.new(seed: seed, genre_mode: mode, random: Random.new(7)).next_songs(40)
  tally = songs.group_by { |s| s.genre&.name || "(none)" }.transform_values(&:size).sort_by { |_, n| -n }
  puts "\ngenre=#{mode}: #{songs.size} songs -> " + tally.map { |g, n| "#{g} #{n}" }.join(", ")
  songs.first(6).each { |s| puts line(s) }
end

# Thumbs, shelving, artist removal, taste and flow are checked by station_engine_test.rb.
