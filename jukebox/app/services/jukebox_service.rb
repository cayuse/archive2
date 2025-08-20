require 'singleton'
require 'json'
require 'time'
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
      cached_songs_count: 0,
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
  # Inserts a manual queue item and does NOT trigger play/skip. Player will naturally advance.
  def add_to_queue(song_id, priority: 'tail')
    song = Song.find(song_id)

    # Determine insert position relative to existing positions
    if priority == 'head'
      # Put before the current minimum position
      min_pos = JukeboxQueueItem.minimum(:position)
      insert_pos = min_pos.nil? ? 0 : (min_pos - 1)
    else
      insert_pos = next_queue_position
    end

    # Persist manual queue item using status '0' (manual)
    JukeboxQueueItem.create!(
      song_id: song_id,
      position: insert_pos,
      status: '0'
    )
  end
  
  # Get current queue
  def queue
    # Manual first, then random, each by position
    JukeboxQueueItem.includes(:song).ordered_for_playback
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
    selected_ids = JukeboxSelectedPlaylist.pluck(:playlist_id)
    if selected_ids.empty?
      Rails.logger.warn "No playlists selected for jukebox - cannot get random songs"
      return []
    end
    
    song_ids = PlaylistsSong.where(playlist_id: selected_ids).pluck(:song_id).uniq
    if song_ids.empty?
      Rails.logger.warn "Selected playlists contain no songs - cannot get random songs"
      return []
    end
    
    ArchiveSong.where(id: song_ids).order('RANDOM()').limit(count)
  end
  
  # Refill random pool (list semantics for Python player)
  def refill_random_pool
    songs = get_random_songs(20)
    songs.each do |song|
      payload = {
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        cached_path: resolve_local_audio_path(song),
        stream_url: generate_stream_url(song)
      }
      @redis.rpush('jukebox:random_pool', payload.to_json)
    end
  end
  
  # Get next random song (if Rails needs to consume it directly)
  def next_random_song
    raw = @redis.rpop('jukebox:random_pool')
    return nil unless raw
    data = JSON.parse(raw) rescue nil
    return nil unless data && data['id']
    
    # Refill pool if getting low
    if @redis.llen('jukebox:random_pool') < 5
      refill_random_pool
    end
    
    Song.find_by(id: data['id'])
  end
  
  # Player control commands (queue JSON commands for Python player)
  def play
    send_command('play')
  end
  
  def pause
    send_command('pause')
  end
  
  def skip
    send_command('skip')
  end
  
  def set_volume(level)
    send_command('set_volume', value: level.to_i)
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
    raw = @redis.get('jukebox:current_song')
    return nil unless raw
    
    # Prefer JSON payload from player; fall back to ID string
    song_id = begin
      data = JSON.parse(raw)
      data['id']
    rescue JSON::ParserError
      raw.to_i
    end
    return nil if song_id.nil? || song_id == 0

    ArchiveSong.includes(:artist, :album).find_by(id: song_id)
  end
  
  # Get cached songs
  def cached_songs
    Song.all
  end
  
  # Get uncached songs
  def uncached_songs
    Song.none
  end
  
  # Cache management
  def cache_song(song_id)
    # No-op: jukebox has full local copy
  end
  
  def clear_cache
    # No-op: jukebox has full local copy
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
    @redis.llen('jukebox:random_pool')
  end
  
  def playing?
    raw = @redis.get('jukebox:status')
    return false unless raw
    begin
      data = JSON.parse(raw)
      data['state'] == 'playing'
    rescue JSON::ParserError
      raw == 'playing'
    end
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
    (JukeboxQueueItem.maximum(:position) || -1) + 1
  end
  
  def resume_if_needed
    # Resume if we have songs and player is paused
    if queue_length > 0 && !playing?
      play
    end
  end

  def send_command(action, payload = {})
    cmd = { action: action }.merge(payload)
    @redis.rpush('jukebox:commands', cmd.to_json)
  end

  # Handle requests from player (e.g., random pool refill)
  def handle_player_requests
    loop do
      raw = @redis.lpop('jukebox:requests')
      break unless raw
      data = JSON.parse(raw) rescue {}
      case data['action']
      when 'refill_random_pool'
        refill_random_pool
      end
    end
  end

  # Attempt to resolve local disk path of the Active Storage blob for a song
  def resolve_local_audio_path(song)
    return nil unless song.respond_to?(:audio_file) && song.audio_file.attached?
    blob = song.audio_file.blob
    return nil unless blob
    service = ActiveStorage::Blob.service
    # Try to use Disk service path_for if available
    if service.respond_to?(:path_for, true)
      begin
        return service.send(:path_for, blob.key)
      rescue
        # fall through to manual
      end
    end
    # Manual path using configured storage root
    root = ENV.fetch('ARCHIVE_STORAGE_ROOT', Rails.root.join('storage').to_s)
    File.join(root.to_s, blob.key[0..1], blob.key[2..3], blob.key)
  end

  def generate_stream_url(song)
    return nil unless song.respond_to?(:audio_file) && song.audio_file.attached?
    host = ENV.fetch('JUKEBOX_PUBLIC_URL', 'http://localhost:3001')
    Rails.application.routes.url_helpers.rails_blob_url(song.audio_file, host: host)
  end
end 