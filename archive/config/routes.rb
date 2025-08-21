Rails.application.routes.draw do
  # Sidekiq Web UI (optional). Protect with basic auth if exposed.
  # require "sidekiq/web"
  # mount Sidekiq::Web => "/sidekiq"
  # PowerSync routes for jukebox synchronization
  # Note: PowerSync is implemented as a custom service, not as a Rails engine
  # mount PowerSync::Engine => '/powersync'
  
  # Theme routes (public access for assets, admin for management)
  get '/themes/:theme.css', to: 'themes#css', as: :theme_css
  get '/themes/:theme/assets/:asset_type/:filename', to: 'themes#asset', as: :theme_asset
  
  # Settings routes (admin only)
  resource :settings, only: [:show, :update] do
    collection do
      get :api_keys
      get :song_types
      get :general
      get :archive_sync
      post :test_connection
      post :force_sync
      post :force_file_sync
      post :generate_slave_key
      post :generate_jukebox_key
      post :perform_initial_sync
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
  end
  
  # Key management routes
  post '/settings/regenerate_slave_key/:id', to: 'settings#regenerate_slave_key', as: :regenerate_slave_key
  post '/settings/deactivate_slave_key/:id', to: 'settings#deactivate_slave_key', as: :deactivate_slave_key
  post '/settings/reactivate_slave_key/:id', to: 'settings#reactivate_slave_key', as: :reactivate_slave_key
  post '/settings/regenerate_jukebox_key/:id', to: 'settings#regenerate_jukebox_key', as: :regenerate_jukebox_key
  post '/settings/deactivate_jukebox_key/:id', to: 'settings#deactivate_jukebox_key', as: :deactivate_jukebox_key
  post '/settings/reactivate_jukebox_key/:id', to: 'settings#reactivate_jukebox_key', as: :reactivate_jukebox_key
  
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
  
  # Upload interface
  resource :upload, only: [:show, :create], controller: 'upload'
  
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
      
      # Archive sync API
      namespace :sync do
        get '/changes', to: 'sync#changes'
        post '/apply', to: 'sync#apply'
        get '/status', to: 'sync#status'
        get '/jukebox_status', to: 'sync#jukebox_status'
        get '/initial_data', to: 'sync#initial_data'
      end
      
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
