class JukeboxController < ApplicationController
  before_action :set_jukebox_service
  
  # GET /api/jukebox/status
  def status
    render json: @jukebox_service.status
  end
  
  # GET /api/jukebox/health
  def health
    render json: @jukebox_service.health
  end
  
  # GET /api/jukebox/sync
  def sync_status
    render json: PowerSyncService.instance.sync_status
  end
  
  # POST /api/jukebox/sync/force
  def force_sync
    PowerSyncService.instance.force_sync
    render json: { message: 'Sync forced successfully' }
  end
  
  # GET /api/jukebox/queue
  def queue
    render json: {
      items: @jukebox_service.queue.map(&:as_json),
      length: @jukebox_service.queue.count
    }
  end
  
  # POST /api/jukebox/queue
  def add_to_queue
    song_id = params[:song_id]
    
    unless song_id
      render json: { error: 'song_id is required' }, status: :bad_request
      return
    end
    
    begin
      queue_item = @jukebox_service.add_to_queue(song_id)
      render json: { 
        message: 'Song added to queue',
        queue_item: queue_item.as_json
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Song not found' }, status: :not_found
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
  
  # DELETE /api/jukebox/queue/:position
  def remove_from_queue
    position = params[:position]&.to_i
    
    unless position
      render json: { error: 'position is required' }, status: :bad_request
      return
    end
    
    if @jukebox_service.remove_from_queue(position)
      render json: { message: 'Song removed from queue' }
    else
      render json: { error: 'Song not found in queue' }, status: :not_found
    end
  end
  
  # DELETE /api/jukebox/queue
  def clear_queue
    @jukebox_service.clear_queue
    render json: { message: 'Queue cleared' }
  end
  
  # POST /api/jukebox/player/play
  def play
    @jukebox_service.play
    render json: { message: 'Play command sent' }
  end
  
  # POST /api/jukebox/player/pause
  def pause
    @jukebox_service.pause
    render json: { message: 'Pause command sent' }
  end
  
  # POST /api/jukebox/player/skip
  def skip
    @jukebox_service.skip
    render json: { message: 'Skip command sent' }
  end
  
  # POST /api/jukebox/player/volume
  def set_volume
    volume = params[:volume]&.to_i
    
    unless volume && volume.between?(0, 100)
      render json: { error: 'Volume must be between 0 and 100' }, status: :bad_request
      return
    end
    
    @jukebox_service.set_volume(volume)
    render json: { message: "Volume set to #{volume}" }
  end
  
  # GET /api/jukebox/search/songs
  def search_songs
    query = params[:q]
    
    unless query
      render json: { error: 'Query parameter q is required' }, status: :bad_request
      return
    end
    
    songs = @jukebox_service.search_songs(query)
    render json: {
      query: query,
      results: songs.map(&:as_json),
      count: songs.count
    }
  end
  
  # GET /api/jukebox/search/artists
  def search_artists
    query = params[:q]
    
    unless query
      render json: { error: 'Query parameter q is required' }, status: :bad_request
      return
    end
    
    artists = @jukebox_service.search_artists(query)
    render json: {
      query: query,
      results: artists.map(&:as_json),
      count: artists.count
    }
  end
  
  # GET /api/jukebox/search/albums
  def search_albums
    query = params[:q]
    
    unless query
      render json: { error: 'Query parameter q is required' }, status: :bad_request
      return
    end
    
    albums = @jukebox_service.search_albums(query)
    render json: {
      query: query,
      results: albums.map(&:as_json),
      count: albums.count
    }
  end
  
  # GET /api/jukebox/search/genres
  def search_genres
    query = params[:q]
    
    unless query
      render json: { error: 'Query parameter q is required' }, status: :bad_request
      return
    end
    
    genres = @jukebox_service.search_genres(query)
    render json: {
      query: query,
      results: genres.map(&:as_json),
      count: genres.count
    }
  end
  
  # GET /api/jukebox/songs/by_artist/:artist
  def songs_by_artist
    artist = params[:artist]
    songs = @jukebox_service.songs_by_artist(artist)
    
    render json: {
      artist: artist,
      songs: songs.map(&:as_json),
      count: songs.count
    }
  end
  
  # GET /api/jukebox/songs/by_album/:album
  def songs_by_album
    album = params[:album]
    songs = @jukebox_service.songs_by_album(album)
    
    render json: {
      album: album,
      songs: songs.map(&:as_json),
      count: songs.count
    }
  end
  
  # GET /api/jukebox/songs/by_genre/:genre
  def songs_by_genre
    genre = params[:genre]
    songs = @jukebox_service.songs_by_genre(genre)
    
    render json: {
      genre: genre,
      songs: songs.map(&:as_json),
      count: songs.count
    }
  end
  
  # GET /api/jukebox/songs/by_year/:year
  def songs_by_year
    year = params[:year]&.to_i
    
    unless year && year.between?(1900, Time.current.year)
      render json: { error: 'Valid year is required' }, status: :bad_request
      return
    end
    
    songs = @jukebox_service.songs_by_year(year)
    
    render json: {
      year: year,
      songs: songs.map(&:as_json),
      count: songs.count
    }
  end
  
  # GET /api/jukebox/playlists/popular
  def popular_playlists
    limit = params[:limit]&.to_i || 10
    playlists = @jukebox_service.popular_playlists(limit)
    
    render json: {
      playlists: playlists.map(&:as_json),
      count: playlists.count
    }
  end
  
  # GET /api/jukebox/songs/recent
  def recent_songs
    limit = params[:limit]&.to_i || 20
    songs = @jukebox_service.recent_songs(limit)
    
    render json: {
      songs: songs.map(&:as_json),
      count: songs.count
    }
  end
  
  # GET /api/jukebox/cache/status
  def cache_status
    cached_songs = @jukebox_service.cached_songs
    uncached_songs = @jukebox_service.uncached_songs
    
    render json: {
      cached_count: cached_songs.count,
      uncached_count: uncached_songs.count,
      total_songs: Song.count,
      cache_percentage: Song.count > 0 ? (cached_songs.count.to_f / Song.count * 100).round(1) : 0
    }
  end
  
  # POST /api/jukebox/cache/song/:song_id
  def cache_song
    song_id = params[:song_id]
    
    unless song_id
      render json: { error: 'song_id is required' }, status: :bad_request
      return
    end
    
    begin
      @jukebox_service.cache_song(song_id)
      render json: { message: 'Song queued for caching' }
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Song not found' }, status: :not_found
    end
  end
  
  # DELETE /api/jukebox/cache
  def clear_cache
    @jukebox_service.clear_cache
    render json: { message: 'Cache cleared' }
  end
  
  private
  
  def set_jukebox_service
    @jukebox_service = JukeboxService.instance
  end
end 