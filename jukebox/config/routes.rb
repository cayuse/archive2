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
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Songs management
  resources :songs, only: [:index, :show] do
    collection do
      get :search
    end
  end

  # Artists management
  resources :artists, only: [:index, :show] do
    collection do
      get :search
    end
  end

  # Albums management
  resources :albums, only: [:index, :show] do
    collection do
      get :search
    end
  end

  # Genres management
  resources :genres, only: [:index, :show] do
    collection do
      get :search
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "songs#index"
end
