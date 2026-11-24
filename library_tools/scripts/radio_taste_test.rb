# Test genre modes and thumbs on staging. Ratings are rolled back at the end.
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

puts "\n--- thumbs"
user = User.first
ActiveRecord::Base.transaction do
  SongRating.where(user: user).delete_all
  base = SongRadio.new(seed: seed, user: user, random: Random.new(3)).next_songs(30)
  disliked_artist = base.map(&:artist_id).compact.tally.max_by { |_, n| n }.first
  down = base.select { |s| s.artist_id == disliked_artist }
  down += Song.where(artist_id: disliked_artist).where.not(id: down.map(&:id)).limit(3).to_a
  up = base.reject { |s| s.artist_id == disliked_artist }.first(4)
  down.each { |s| SongRating.rate!(user: user, song: s, value: -1) }
  up.each { |s| SongRating.rate!(user: user, song: s, value: 1) }
  puts "thumbed down #{down.size} songs by #{Artist.find(disliked_artist).name}; thumbed up: #{up.map(&:title).join(' | ')[0, 90]}"

  after = SongRadio.new(seed: seed, user: user, random: Random.new(3)).next_songs(30)
  puts "before: #{base.count { |s| s.artist_id == disliked_artist }} of 30 by that artist; after: #{after.count { |s| s.artist_id == disliked_artist }} of 30"
  puts "thumbed-down songs in the new stream: #{(after.map(&:id) & down.map(&:id)).size}"
  near = SongNeighbor.where(song_id: up.map(&:id)).pluck(:neighbor_id).to_set
  puts "songs that sound like a thumbs-up: before #{base.count { |s| near.include?(s.id) }}, after #{after.count { |s| near.include?(s.id) }}"
  puts "toggle off: rate! 0 -> #{SongRating.rate!(user: user, song: up.first, value: 0)}, rows now #{SongRating.where(user: user).count}"
  raise ActiveRecord::Rollback
end
puts "rolled back; ratings in table: #{SongRating.count}"
