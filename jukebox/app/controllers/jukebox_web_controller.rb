class JukeboxWebController < ApplicationController
  before_action :set_jukebox_service
  
  # GET /live
  def live
    # Now playing is the last song added to the played list
    @current_song = JukeboxPlayedSong.order(played_at: :desc).includes(song: [:artist, :album]).first&.song
    @queue_items = JukeboxQueueItem.ordered_for_playback.includes(:song).limit(10)
    @status = @jukebox_service.status
    @upcoming_songs = get_upcoming_songs
  end
  
  # GET /live/status.json - JSON API for player status
  def live_status
    render json: {
      player_status: @jukebox_service.status,
      current_song: @jukebox_service.current_song
    }
  end
  
  # GET /live/upcoming.json - JSON API for upcoming songs
  def live_upcoming
    render json: {
      upcoming_songs: get_upcoming_songs
    }
  end
  
  # GET /
  def index
    @status = @jukebox_service.status
    @health = @jukebox_service.health
    @sync_status = PowerSyncService.instance.sync_status
    @recent_songs = @jukebox_service.recent_songs(10)
    @popular_playlists = @jukebox_service.popular_playlists(5)
  end
  
  # GET /search
  def search
    @query = params[:q]
    @results = {}
    
    if @query.present?
      @results[:songs] = @jukebox_service.search_songs(@query)
      @results[:artists] = @jukebox_service.search_artists(@query)
      @results[:albums] = @jukebox_service.search_albums(@query)
      @results[:genres] = @jukebox_service.search_genres(@query)
    end
  end
  
  # GET /browse
  def browse
    @artists = Artist.order(:name).limit(50)
    @albums = Album.order(:title).limit(50)
    @genres = Genre.order(:name).limit(20)
    @years = Song.distinct.pluck(:year).compact.sort.reverse
  end
  
  # GET /queue
  def queue
    @queue_items = @jukebox_service.queue
    @status = @jukebox_service.status
  end
  
  # GET /cache
  def cache
    @cached_songs = @jukebox_service.cached_songs
    @uncached_songs = @jukebox_service.uncached_songs
    @cache_status = {
      cached_count: @cached_songs.count,
      uncached_count: @uncached_songs.count,
      total_songs: Song.count,
      cache_percentage: Song.count > 0 ? (@cached_songs.count.to_f / Song.count * 100).round(1) : 0
    }
  end
  
  # GET /sync
  def sync
    @sync_status = PowerSyncService.instance.sync_status
    @sync_data = @jukebox_service.sync_status
  end
  
  private
  
  def set_jukebox_service
    @jukebox_service = JukeboxService.instance
  end
  
  def get_upcoming_songs
    # Upcoming is exactly the unified queue (manual first, then random), capped to 10
    queue_items = JukeboxQueueItem.ordered_for_playback.includes(:song).limit(10)
    queue_items.map do |item|
      {
        song: {
          id: item.song.id,
          title: item.song.title,
          artist_name: item.song.artist&.name,
          album_name: item.song.album&.title,
          duration: item.song.duration
        },
        position: item.position,
        source: item.status.to_s == '1' ? 'random' : 'queue',
        order_number: item.position
      }
    end
  end
end 