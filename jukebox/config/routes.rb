Rails.application.routes.draw do
  # API proxy to Python player HTTP API (controller: Api::PlayerController)
  namespace :api do
    # Player status endpoints (public, no authentication required)
    get   'player/status',        to: 'player#status'
    match 'player/volume',        to: 'player#volume', via: [:get, :post]
    get   'player/current_song',  to: 'player#current_song'
    get   'player/progress',      to: 'player#progress'
    get   'player/queue',         to: 'player#queue'
    get   'player/health',        to: 'player#health'
    
    # Player control endpoints (require authentication)
    post  'player/play',          to: 'player#play'
    post  'player/pause',         to: 'player#pause'
    post  'player/stop',          to: 'player#stop'
    post  'player/next',          to: 'player#next'
    post  'player/volume_up',     to: 'player#volume_up'
    post  'player/volume_down',   to: 'player#volume_down'
  end
  
  # Jukebox controller UI
  get  '/system/player',   to: 'system#index', as: :system_player
  post '/system/play',     to: 'system#play',  as: :system_play
  post '/system/pause',    to: 'system#pause', as: :system_pause
  post '/system/stop',     to: 'system#stop',  as: :system_stop
  post '/system/next',     to: 'system#next',  as: :system_next
  post '/system/skip',     to: 'system#next',  as: :system_skip
  post '/system/volume_up', to: 'system#volume_up', as: :system_volume_up
  post '/system/volume_down', to: 'system#volume_down', as: :system_volume_down
  post '/system/set_volume', to: 'system#set_volume', as: :system_set_volume
  
  # Session routes
  get 'login', to: 'sessions#new'
  post 'login', to: 'sessions#create'
  delete 'logout', to: 'sessions#destroy'
  
  # System configuration routes (admin only)
  get 'system', to: 'system_config#index'
  get  'system/themes', to: 'system_config#themes'
  post 'system/themes', to: 'system_config#themes'
  get 'system/settings', to: 'system_config#settings'
  
  # Theme routes
  get 'themes/:theme.css', to: 'themes#css'
  get 'themes/:theme/assets/:asset_type/:filename', to: 'themes#asset'
  
  # Settings routes
  get 'settings', to: 'settings#index'
  post 'settings/themes/:id/activate', to: 'settings#activate_theme', as: :activate_theme_settings
  
  # Archive sync routes (admin only)
  get 'archive_sync', to: 'archive_sync#index'
  patch 'archive_sync', to: 'archive_sync#update'
  post 'archive_sync/test_connection', to: 'archive_sync#test_connection'
  post 'archive_sync/force_sync', to: 'archive_sync#force_sync'
  
  # Admin routes
  get 'admin', to: 'admin#index'
  
  # Jukebox web interface routes
  get 'live', to: 'jukebox_web#live'
  get 'search', to: 'jukebox_web#search'
  get 'browse', to: 'jukebox_web#browse'
  get 'queue', to: 'jukebox_web#queue'
  get 'cache', to: 'jukebox_web#cache'
  get 'sync', to: 'jukebox_web#sync'
  
  # Resource routes for main entities
  resources :artists
  resources :songs do
    collection do
      get :search
    end
  end
  resources :albums
  resources :genres
  resources :playlists

  # Admin: configure random source playlists
  get 'system/random_sources', to: 'system_config#random_sources'
  post 'system/random_sources', to: 'system_config#random_sources'
  
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
      # Stable stream URL for MPD
      get  'player/stream/:id', to: 'jukebox#stream'
      # Next song for player (queue-aware)
      get  'player/next', to: 'jukebox#next_song'
      
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
    
    # Player API - direct communication with Python player via Redis
    namespace :player do
      # Status endpoints (public)
      get 'status', to: 'player#status'
      match 'volume', to: 'player#volume', via: [:get, :post]
      get 'current_song', to: 'player#current_song'
      get 'progress', to: 'player#progress'
      get 'queue', to: 'player#queue'
      get 'health', to: 'player#health'
      
      # Control endpoints (require authentication)
      post 'play', to: 'player#play'
      post 'pause', to: 'player#pause'
      post 'stop', to: 'player#stop'
      post 'next', to: 'player#next'
      post 'volume_up', to: 'player#volume_up'
      post 'volume_down', to: 'player#volume_down'
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "jukebox_web#live"
end
