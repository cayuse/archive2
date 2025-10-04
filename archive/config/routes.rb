Rails.application.routes.draw do
  # Sidekiq Web UI (optional). Protect with basic auth if exposed.
  # require "sidekiq/web"
  # mount Sidekiq::Web => "/sidekiq"

  # Mount ActionCable for WebSocket connections
  mount ActionCable.server => '/cable'

  
  # Theme routes (public access for assets, admin for management)
  get '/themes/:theme.css', to: 'themes#css', as: :theme_css
  get '/themes/:theme/assets/:asset_type/:filename', to: 'themes#asset', as: :theme_asset
  
  # Settings routes (admin only)
  resource :settings, only: [:show, :update] do
    collection do
      get :general
    end
  end
  

  

  
  # Theme management routes
  get 'themes', to: 'settings#themes', as: :manage_themes
  get 'themes/new', to: 'settings#new_theme', as: :new_manage_theme
  post 'themes', to: 'settings#create_theme'
  get 'themes/:id', to: 'settings#show_theme', as: :manage_theme
  get 'themes/:id/edit', to: 'settings#edit_theme', as: :edit_manage_theme
  patch 'themes/:id', to: 'settings#update_theme'
  put 'themes/:id', to: 'settings#update_theme'
  delete 'themes/:id', to: 'settings#destroy_theme'
  get 'themes/:id/export', to: 'settings#export_theme', as: :export_manage_theme
  get 'themes/:id/preview', to: 'settings#preview_theme', as: :preview_manage_theme
  post 'themes/:id/duplicate', to: 'settings#duplicate_theme', as: :duplicate_manage_theme
  post 'themes/:id/switch', to: 'settings#switch_theme', as: :switch_theme
  

  
  # Authentication routes
  get '/login', to: 'sessions#new', as: :login
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy', as: :logout
  get '/logout', to: 'sessions#destroy'  # Allow GET for easier logout
  
  # User management routes (admin only)
  resources :users, except: [:show] do
    member do
      post :reset_password
      patch :set_password
    end
  end
  
  # Profile routes (users can edit their own profile)
  resource :profile, only: [:show, :edit, :update], controller: 'profile'
  
  # Songs management
  resources :songs do
    collection do
      get :search
      get :maintenance
      post :bulk_update
    end
  end
  
  # Album search for autocomplete
  get '/albums/search', to: 'albums#search'
  
  # Artist search for autocomplete
  get '/artists/search', to: 'artists#search'
  
  # Genre search for autocomplete
  get '/genres/search', to: 'genres#search'
  
  # Artists management
  resources :artists, only: [:index, :show]
  
  # Albums management
  resources :albums, only: [:index, :show]
  
  # Genres management
  resources :genres, only: [:index, :show]
  
  # Playlists management
  resources :playlists, only: [:index, :show, :create, :update] do
    member do
      post :reorder
      post :add_songs
      delete :remove_songs
    end
  end
  
  # Jukeboxes management
  resources :jukeboxes do
    member do
      post :start
      post :pause
      post :resume
      post :end
      post :reset
      get :player
      get :guest
    end
  end
  
  # Upload interface
  resource :upload, only: [:show, :create], controller: 'upload'
  
  # API routes
  namespace :api do
    namespace :v1 do
      resources :songs, only: [:show] do
        member do
          get :download
          get :stream
        end
      end
      
      resources :jukeboxes, only: [] do
        member do
          get :status
          get :queue
          get :current_song
          get :next_song
          get :playback_info
          post :queue, action: :add_to_queue
          delete 'queue/:song_id', action: :remove_from_queue
          patch 'queue/:song_id', action: :move_in_queue
          post :playback_status
        end
      end
      
      # Guest access routes (read-only, password-protected)
      scope 'guest/:jukebox_id' do
        get 'test', to: 'guest#test'
        get 'status', to: 'guest#status'
        get 'current_song', to: 'guest#current_song'
        get 'queue', to: 'guest#queue'
        get 'playback_info', to: 'guest#playback_info'
        get 'search_songs', to: 'guest#search_songs'
        post 'request_song', to: 'guest#request_song'
      end
    end
  end
  
  # Bulk operations (moderator/admin only)
  resource :bulk_operations, only: [:show] do
    collection do
      post :upload_csv
      get :export_csv
      post :bulk_delete
    end
  end
  
  # API Routes for external access and bulk operations
  namespace :api do
    namespace :v1 do
      # Authentication for API
      post '/auth/login', to: 'auth#login'
      post '/auth/logout', to: 'auth#logout'
      get '/auth/verify', to: 'auth#verify'
      

      
      # Bulk song operations (admin/moderator only)
      resources :songs, only: [:index, :show] do
        collection do
          post :bulk_create
          put :bulk_update
          delete :bulk_destroy
          post :bulk_upload
          post :direct_upload
          post :create_from_blob
          get :export
        end
      end
      
      # Artist management
      resources :artists, only: [:index, :show] do
        collection do
          post :bulk_create
          get :export
        end
      end
      
      # Album management
      resources :albums, only: [:index, :show] do
        collection do
          post :bulk_create
          get :export
        end
      end
      
      # Genre management
      resources :genres, only: [:index, :show] do
        collection do
          post :bulk_create
          get :export
        end
      end
      
      # Playlist operations (for music player integration)
      resources :playlists, only: [:index, :show] do
        member do
          post :add_song
          delete :remove_song
          put :reorder_songs
        end
      end
      
      # Audio file streaming (for music player)
      resources :audio_files, only: [:show] do
        member do
          get :stream
          get :download
        end
      end
      
      # Health check for load balancers
      get '/health', to: 'health#show'
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "songs#index"
end
