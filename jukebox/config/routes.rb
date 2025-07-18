Rails.application.routes.draw do
  # Jukebox web interface routes
  get 'search', to: 'jukebox_web#search'
  get 'browse', to: 'jukebox_web#browse'
  get 'queue', to: 'jukebox_web#queue'
  get 'cache', to: 'jukebox_web#cache'
  get 'sync', to: 'jukebox_web#sync'
  
  # Jukebox API routes
  namespace :api do
    namespace :jukebox do
      # System status and health
      get 'status', to: 'jukebox#status'
      get 'health', to: 'jukebox#health'
      
      # Sync management
      get 'sync', to: 'jukebox#sync_status'
      post 'sync/force', to: 'jukebox#force_sync'
      
      # Queue management
      get 'queue', to: 'jukebox#queue'
      post 'queue', to: 'jukebox#add_to_queue'
      delete 'queue', to: 'jukebox#clear_queue'
      delete 'queue/:position', to: 'jukebox#remove_from_queue'
      
      # Player control
      post 'player/play', to: 'jukebox#play'
      post 'player/pause', to: 'jukebox#pause'
      post 'player/skip', to: 'jukebox#skip'
      post 'player/volume', to: 'jukebox#set_volume'
      
      # Search functionality
      get 'search/songs', to: 'jukebox#search_songs'
      get 'search/artists', to: 'jukebox#search_artists'
      get 'search/albums', to: 'jukebox#search_albums'
      get 'search/genres', to: 'jukebox#search_genres'
      
      # Browse by category
      get 'songs/by_artist/:artist', to: 'jukebox#songs_by_artist'
      get 'songs/by_album/:album', to: 'jukebox#songs_by_album'
      get 'songs/by_genre/:genre', to: 'jukebox#songs_by_genre'
      get 'songs/by_year/:year', to: 'jukebox#songs_by_year'
      
      # Playlists and recent content
      get 'playlists/popular', to: 'jukebox#popular_playlists'
      get 'songs/recent', to: 'jukebox#recent_songs'
      
      # Cache management
      get 'cache/status', to: 'jukebox#cache_status'
      post 'cache/song/:song_id', to: 'jukebox#cache_song'
      delete 'cache', to: 'jukebox#clear_cache'
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "jukebox_web#index"
end
