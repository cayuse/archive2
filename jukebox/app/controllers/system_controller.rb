class SystemController < ApplicationController
  # before_action :require_login  # Temporarily disabled for testing
  before_action :set_redis

  def index
    # Get real-time status from Python player API
    @player_status = get_player_status
    @current_volume = @player_status&.dig('volume') || 80
    @current_song = @player_status&.dig('current_song')
    @player_state = @player_status&.dig('state') || 'unknown'
    @is_connected = @player_status&.dig('connected') || false
    
    # Fallback to Redis if API fails
    if !@is_connected
      @status = begin
        raw = @redis.get('jukebox:status')
        raw ? JSON.parse(raw) : { 'state' => 'unknown' }
      rescue => e
        Rails.logger.error "Failed to get status from Redis: #{e.message}"
        { 'state' => 'unknown' }
      end
      
      @current_song = begin
        raw = @redis.get('jukebox:current_song')
        raw ? JSON.parse(raw) : nil
      rescue => e
        Rails.logger.error "Failed to get current song from Redis: #{e.message}"
        nil
      end
      
      @current_volume = begin
        raw = @redis.get('jukebox:current_volume')
        if raw
          raw.to_i
        else
          Rails.logger.info "No volume found in Redis, using default 80%"
          80
        end
      rescue => e
        Rails.logger.error "Failed to get volume from Redis: #{e.message}"
        80  # Default volume
      end
    end
  end

  def play
    enqueue_command(action: 'play')
    redirect_to system_path, notice: 'Play requested'
  end

  def pause
    enqueue_command(action: 'pause')
    redirect_to system_path, notice: 'Pause requested'
  end

  def stop
    enqueue_command(action: 'stop')
    redirect_to system_path, notice: 'Stop requested'
  end

  def next
    enqueue_command(action: 'next')
    redirect_to system_path, notice: 'Skip requested'
  end

  def volume_up
    current_vol = @current_volume || 80
    new_volume = [current_vol + 10, 100].min  # Don't exceed 100%
    enqueue_command(action: 'volume', volume: new_volume)
    redirect_to system_path, notice: "Volume increased to #{new_volume}%"
  end

  def volume_down
    current_vol = @current_volume || 80
    new_volume = [current_vol - 10, 0].max  # Don't go below 0%
    enqueue_command(action: 'volume', volume: new_volume)
    redirect_to system_path, notice: "Volume decreased to #{new_volume}%"
  end

  def set_volume
    # Handle both form and JSON requests
    volume = if request.content_type == 'application/json'
      JSON.parse(request.body.read)['volume']
    else
      params[:volume]
    end
    
    volume = volume.to_i
    volume = [[0, volume].max, 100].min  # Clamp between 0-100
    
    # Debug logging
    Rails.logger.info "Setting volume to: #{volume}%"
    
    enqueue_command(action: 'volume', volume: volume)
    
    # Respond appropriately based on request type
    if request.content_type == 'application/json'
      render json: { success: true, volume: volume, message: "Volume set to #{volume}%" }
    else
      redirect_to system_path, notice: "Volume set to #{volume}%"
    end
  end

  private

  def get_player_status
    begin
      response = HTTP.get("#{player_api_url}/api/player/status")
      if response.status.success?
        JSON.parse(response.body.to_s)
      else
        nil
      end
    rescue => e
      Rails.logger.error "Error getting player status: #{e.message}"
      nil
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

  def enqueue_command(payload)
    @redis.rpush('jukebox:commands', payload.to_json)
  end
end


