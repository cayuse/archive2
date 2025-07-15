Rails.application.routes.draw do
  # Settings routes (admin only)
  resource :settings, only: [:show, :update] do
    collection do
      get :theme
      get :api_keys
      get :song_types
      get :general
    end
  end
  # Authentication routes
  get '/login', to: 'sessions#new', as: :login
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy', as: :logout
  
  # User management routes (admin only)
  resources :users, except: [:show]
  
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
  
  # Artists management
  resources :artists, only: [:index, :show]
  
  # Albums management
  resources :albums, only: [:index, :show]
  
  # Genres management
  resources :genres, only: [:index, :show]
  
  # Playlists management
  resources :playlists, only: [:index, :show]
  
  # Album search for autocomplete
  get '/albums/search', to: 'albums#search'
  
  # Artist search for autocomplete
  get '/artists/search', to: 'artists#search'
  
  # Genre search for autocomplete
  get '/genres/search', to: 'genres#search'
  
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
      
      # Bulk song operations (admin/moderator only)
      resources :songs, only: [:index, :show] do
        collection do
          post :bulk_create
          put :bulk_update
          delete :bulk_destroy
          post :bulk_upload
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
