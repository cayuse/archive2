class Api::PlayerController < ApplicationController
  before_action :set_redis
  
  # Public endpoints (no authentication required)
  before_action :require_login, only: [:play, :pause, :stop, :next, :set_volume, :volume_up, :volume_down]
  
  # Get comprehensive player status from Redis
  def status
    begin
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        # Convert all values to proper types and return
        render json: status_data
      else
        render json: { error: "No player status available" }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error getting player status from Redis: #{e.message}"
      render json: { error: "Redis error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get current volume from Redis status
  def volume
    if request.method == "GET"
      get_volume
    elsif request.method == "POST"
      set_volume
    end
  end
  
  # Get current song information from Redis status
  def current_song
    begin
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        current_song_metadata = status_data['current_song_metadata']
        if current_song_metadata.present?
          begin
            song_data = JSON.parse(current_song_metadata)
            render json: song_data
          rescue JSON::ParserError
            render json: { error: "Invalid song metadata format" }, status: :internal_server_error
          end
        else
          render json: { error: "No current song" }, status: :not_found
        end
      else
        render json: { error: "No player status available" }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error getting current song from Redis: #{e.message}"
      render json: { error: "Redis error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get playback progress from Redis status
  def progress
    begin
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        progress_data = {
          elapsed_seconds: status_data['elapsed_seconds'],
          duration_seconds: status_data['duration_seconds'],
          remaining_seconds: status_data['remaining_seconds'],
          progress_percent: status_data['progress_percent'],
          time_until_next_request: status_data['time_until_next_request']
        }
        render json: progress_data
      else
        render json: { error: "No player status available" }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error getting progress from Redis: #{e.message}"
      render json: { error: "Redis error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get current queue/playlist from Redis status
  def queue
    begin
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        # For now, return basic queue info - we can expand this later
        queue_data = {
          playlist_length: status_data['playlist_length'],
          current_song_metadata: status_data['current_song_metadata']
        }
        render json: queue_data
      else
        render json: { error: "No player status available" }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error getting queue from Redis: #{e.message}"
      render json: { error: "Redis error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Health check - check if Redis is accessible and has player status
  def health
    begin
      # Check if Redis is accessible
      @redis.ping
      
      # Check if we have player status
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        health_status = {
          status: 'healthy',
          redis: 'connected',
          player_status: 'available',
          timestamp: status_data['timestamp'],
          health: status_data['health'] || 'unknown'
        }
        render json: health_status
      else
        health_status = {
          status: 'degraded',
          redis: 'connected',
          player_status: 'unavailable',
          message: 'Redis connected but no player status found'
        }
        render json: health_status, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Health check failed: #{e.message}"
      health_status = {
        status: 'unhealthy',
        redis: 'disconnected',
        player_status: 'unavailable',
        error: e.message
      }
      render json: health_status, status: :service_unavailable
    end
  end
  
  # Player control commands (require authentication)
  def play
    enqueue_command(action: 'play')
    render json: { success: true, message: 'Play command sent' }
  end
  
  def pause
    enqueue_command(action: 'pause')
    render json: { success: true, message: 'Pause command sent' }
  end
  
  def stop
    enqueue_command(action: 'stop')
    render json: { success: true, message: 'Stop command sent' }
  end
  
  def next
    enqueue_command(action: 'next')
    render json: { success: true, message: 'Next command sent' }
  end
  
  def volume_up
    enqueue_command(action: 'volume_up')
    render json: { success: true, message: 'Volume up command sent' }
  end
  
  def volume_down
    enqueue_command(action: 'volume_down')
    render json: { success: true, message: 'Volume down command sent' }
  end
  
  private
  
  def get_volume
    begin
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        volume = status_data['volume'] || '0'
        render json: { volume: volume.to_i }
      else
        render json: { error: "No player status available" }, status: :not_found
      end
    rescue => e
      Rails.logger.error "Error getting volume from Redis: #{e.message}"
      render json: { error: "Redis error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  def set_volume
    # This endpoint will be handled by the system controller for authenticated users
    # We'll redirect volume commands to the command queue
    begin
      volume = params[:volume].to_i
      volume = [[0, volume].max, 100].min  # Clamp between 0-100
      
      # Add command to Redis queue
      command = { action: 'set_volume', value: volume }
      @redis.rpush('jukebox:commands', command.to_json)
      
      render json: { success: true, volume: volume, message: "Volume command queued" }
    rescue => e
      Rails.logger.error "Error setting volume: #{e.message}"
      render json: { error: "Failed to queue volume command: #{e.message}" }, status: :internal_server_error
    end
  end
  
  def enqueue_command(payload)
    @redis.rpush('jukebox:commands', payload.to_json)
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
