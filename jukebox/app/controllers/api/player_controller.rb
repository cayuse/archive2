class Api::PlayerController < ApplicationController
  before_action :set_redis
  
  # Get comprehensive player status
  def status
    begin
      response = HTTP.get("#{player_api_url}/api/player/status")
      if response.status.success?
        render json: JSON.parse(response.body.to_s)
      else
        render json: { error: "Failed to get player status" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error getting player status: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get current volume
  def volume
    if request.method == "GET"
      get_volume
    elsif request.method == "POST"
      set_volume
    end
  end
  
  # Get current song information
  def current_song
    begin
      response = HTTP.get("#{player_api_url}/api/player/current_song")
      if response.status.success?
        render json: JSON.parse(response.body.to_s)
      else
        render json: { error: "Failed to get current song" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error getting current song: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get playback progress
  def progress
    begin
      response = HTTP.get("#{player_api_url}/api/player/progress")
      if response.status.success?
        render json: JSON.parse(response.body.to_s)
      else
        render json: { error: "Failed to get progress" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error getting progress: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get current queue/playlist
  def queue
    begin
      response = HTTP.get("#{player_api_url}/api/player/queue")
      if response.status.success?
        render json: JSON.parse(response.body.to_s)
      else
        render json: { error: "Failed to get queue" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error getting queue: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Health check
  def health
    begin
      response = HTTP.get("#{player_api_url}/api/player/health")
      if response.status.success?
        render json: JSON.parse(response.body.to_s)
      else
        render json: { error: "Player health check failed" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error checking player health: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  private
  
  def get_volume
    begin
      response = HTTP.get("#{player_api_url}/api/player/volume")
      if response.status.success?
        render json: JSON.parse(response.body.to_s)
      else
        render json: { error: "Failed to get volume" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error getting volume: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  def set_volume
    begin
      volume = params[:volume].to_i
      volume = [[0, volume].max, 100].min  # Clamp between 0-100
      
      response = HTTP.post("#{player_api_url}/api/player/volume", 
                          json: { volume: volume })
      
      if response.status.success?
        result = JSON.parse(response.body.to_s)
        render json: result
      else
        render json: { error: "Failed to set volume" }, status: :bad_request
      end
    rescue => e
      Rails.logger.error "Error setting volume: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  def player_api_url
    ENV.fetch('PLAYER_API_URL', 'http://localhost:5000')
  end
  
  def set_redis
    url = ENV['REDIS_URL']
    if url.present?
      @redis = Redis.new(url: url)
    else
      host = ENV.fetch('REDIS_HOST', 'localhost')
      port = ENV.fetch('REDIS_PORT', '6379').to_i
      db   = ENV.fetch('REDIS_DB', '1').to_i
      @redis = Redis.new(host: host, port: port, db: db)
    end
  end
end
