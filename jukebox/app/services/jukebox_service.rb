class JukeboxService
  include Singleton
  
  def initialize
    @redis = Redis.new(
      host: ENV.fetch('REDIS_HOST', 'localhost'),
      port: ENV.fetch('REDIS_PORT', 6379),
      db: ENV.fetch('REDIS_DB', 0)
    )
  end
  
  # Get current system status
  def status
    {
      current_song: current_song,
      queue_length: queue_length,
      random_pool_size: random_pool_size,
      is_playing: playing?,
      volume: volume,
      cached_songs_count: cached_songs_count,
      synced_songs_count: synced_songs_count,
      last_sync: last_sync_time
    }
  end
  
  # Get system health and recommendations
  def health
    status = self.status
    recommendations = []
    
    # Check if we have any synced songs
    if status[:synced_songs_count] == 0
      recommendations << "No songs synced from archive. Check PowerSync connection."
    end
    
    # Check if we have cached songs
    if status[:cached_songs_count] == 0
      recommendations << "No songs cached locally. Songs will be downloaded when queued."
    end
    
    # Check if player is paused due to no content
    if !status[:is_playing] && status[:queue_length] == 0 && status[:random_pool_size] == 0
      recommendations << "Player is paused. Add songs to queue or configure playlists to resume."
    end
    
    # Check sync status
    if status[:last_sync].nil? || Time.current - status[:last_sync] > 5.minutes
      recommendations << "Archive sync may be delayed. Check network connection."
    end
    
    {
      status: status,
      recommendations: recommendations,
      healthy: recommendations.empty?
    }
  end
  
  # Add song to queue
  def add_to_queue(song_id)
    song = Song.find(song_id)
    
    # Check if song is cached, if not, queue it for download
    unless song.cached?
      DownloadSongJob.perform_later(song_id)
    end
    
    # Add to queue
    queue_item = JukeboxQueueItem.create!(
      song_id: song_id,
      position: next_queue_position,
      added_at: Time.current
    )
    
    # Update Redis
    @redis.lpush('jukebox:queue', song_id.to_s)
    
    # Resume playback if paused
    resume_if_needed
    
    queue_item
  end
  
  # Get current queue
  def queue
    JukeboxQueueItem.includes(:song).order(:position)
  end
  
  # Remove song from queue
  def remove_from_queue(position)
    queue_item = JukeboxQueueItem.find_by(position: position)
    return false unless queue_item
    
    # Remove from Redis
    @redis.lrem('jukebox:queue', 0, queue_item.song_id.to_s)
    
    # Update positions
    JukeboxQueueItem.where('position > ?', position).update_all('position = position - 1')
    
    queue_item.destroy
    true
  end
  
  # Clear entire queue
  def clear_queue
    JukeboxQueueItem.destroy_all
    @redis.del('jukebox:queue')
  end
  
  # Get random songs from playlists
  def get_random_songs(count = 10)
    # Get all public playlists
    playlists = JukeboxPlaylist.where(is_public: true)
    
    # Get all songs from these playlists
    song_ids = JukeboxPlaylistSong.joins(:jukebox_playlist)
                           .where(jukebox_playlists: { is_public: true })
                           .pluck(:song_id)
                           .uniq
    
    # Return random selection
    Song.where(id: song_ids).order('RANDOM()').limit(count)
  end
  
  # Refill random pool
  def refill_random_pool
    songs = get_random_songs(20)
    songs.each do |song|
      @redis.sadd('jukebox:random_pool', song.id.to_s)
    end
  end
  
  # Get next random song
  def next_random_song
    song_id = @redis.spop('jukebox:random_pool')
    return nil unless song_id
    
    # Refill pool if getting low
    if @redis.scard('jukebox:random_pool') < 5
      refill_random_pool
    end
    
    Song.find(song_id)
  end
  
  # Player control commands
  def play
    @redis.set('jukebox:command', 'play')
    @redis.expire('jukebox:command', 10)
  end
  
  def pause
    @redis.set('jukebox:command', 'pause')
    @redis.expire('jukebox:command', 10)
  end
  
  def skip
    @redis.set('jukebox:command', 'skip')
    @redis.expire('jukebox:command', 10)
  end
  
  def set_volume(level)
    @redis.set('jukebox:volume', level.to_i)
    @redis.set('jukebox:command', 'volume')
    @redis.expire('jukebox:command', 10)
  end
  
  # Search functionality using synced data
  def search_songs(query)
    Song.search(query).limit(50)
  end
  
  def search_artists(query)
    Artist.search(query).limit(20)
  end
  
  def search_albums(query)
    Album.search(query).limit(20)
  end
  
  def search_genres(query)
    Genre.search(query).limit(10)
  end
  
  # Get songs by artist
  def songs_by_artist(artist_name)
    Song.by_artist(artist_name)
  end
  
  # Get songs by album
  def songs_by_album(album_title)
    Song.by_album(album_title)
  end
  
  # Get songs by genre
  def songs_by_genre(genre_name)
    Song.by_genre(genre_name)
  end
  
  # Get songs by year
  def songs_by_year(year)
    Song.by_year(year)
  end
  
  # Get popular playlists
  def popular_playlists(limit = 10)
    JukeboxPlaylist.where(is_public: true)
            .joins(:jukebox_playlist_songs)
            .group('jukebox_playlists.id')
            .order('COUNT(jukebox_playlist_songs.id) DESC')
            .limit(limit)
  end
  
  # Get recently added songs
  def recent_songs(limit = 20)
    Song.order(created_at: :desc).limit(limit)
  end
  
  # Get current song
  def current_song
    song_id = @redis.get('jukebox:current_song')
    return nil unless song_id
    
    song = Song.find_by(id: song_id)
    return nil unless song
    
    {
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      cached: song.cached?
    }
  end
  
  # Get cached songs
  def cached_songs
    Song.joins(:jukebox_cached_song)
  end
  
  # Get uncached songs
  def uncached_songs
    Song.left_joins(:jukebox_cached_song).where(jukebox_cached_songs: { id: nil })
  end
  
  # Cache management
  def cache_song(song_id)
    DownloadSongJob.perform_later(song_id)
  end
  
  def clear_cache
    JukeboxCachedSong.destroy_all
    FileUtils.rm_rf(Rails.root.join('storage', 'cached_songs'))
    FileUtils.mkdir_p(Rails.root.join('storage', 'cached_songs'))
  end
  
  # Sync status
  def sync_status
    {
      last_sync: last_sync_time,
      songs_count: Song.count,
      artists_count: Artist.count,
      albums_count: Album.count,
      genres_count: Genre.count,
      playlists_count: JukeboxPlaylist.count,
      users_count: User.count
    }
  end
  
  private
  
  def queue_length
    @redis.llen('jukebox:queue')
  end
  
  def random_pool_size
    @redis.scard('jukebox:random_pool')
  end
  
  def playing?
    @redis.get('jukebox:status') == 'playing'
  end
  
  def volume
    @redis.get('jukebox:volume')&.to_i || 80
  end
  
  def cached_songs_count
    JukeboxCachedSong.count
  end
  
  def synced_songs_count
    Song.count
  end
  
  def last_sync_time
    last_sync = @redis.get('jukebox:last_sync')
    last_sync ? Time.parse(last_sync) : nil
  end
  
  def next_queue_position
    JukeboxQueueItem.maximum(:position) || 0
  end
  
  def resume_if_needed
    # Resume if we have songs and player is paused
    if queue_length > 0 && !playing?
      play
    end
  end
end 