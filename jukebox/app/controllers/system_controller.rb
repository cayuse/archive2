class SystemController < ApplicationController
  before_action :require_login  # Require authentication for all player controls
  before_action :set_redis

  def index
    # Get real-time status directly from Redis
    @player_status = get_player_status_from_redis
    @current_volume = @player_status&.dig('volume')&.to_i || 80
    @current_song = parse_current_song(@player_status)
    @player_state = @player_status&.dig('desired_state') || 'unknown'
    @is_connected = @player_status&.dig('health') == 'healthy'
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
    enqueue_command(action: 'volume_up')
    redirect_to system_path, notice: "Volume increased to #{new_volume}%"
  end

  def volume_down
    current_vol = @current_volume || 80
    new_volume = [current_vol - 10, 0].max  # Don't go below 0%
    enqueue_command(action: 'volume_down')
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
    
    enqueue_command(action: 'set_volume', value: volume)
    
    # Respond appropriately based on request type
    if request.content_type == 'application/json'
      render json: { success: true, volume: volume, message: "Volume set to #{volume}%" }
    else
      redirect_to system_path, notice: "Volume set to #{volume}%"
    end
  end

  private

  def get_player_status_from_redis
    begin
      status_data = @redis.hgetall('jukebox:player_status')
      if status_data.any?
        # Convert numeric values to proper types
        status_data.each do |key, value|
          if ['elapsed_seconds', 'duration_seconds', 'remaining_seconds', 'volume', 'crossfade_seconds', 'time_until_next_request', 'progress_percent'].include?(key)
            status_data[key] = value.to_f if value.present?
          end
        end
        status_data
      else
        nil
      end
    rescue => e
      Rails.logger.error "Error getting player status from Redis: #{e.message}"
      nil
    end
  end

  def parse_current_song(status_data)
    return nil unless status_data&.dig('current_song_metadata')
    
    begin
      song_metadata = status_data['current_song_metadata']
      if song_metadata.present? && song_metadata != '{}'
        JSON.parse(song_metadata)
      else
        nil
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Error parsing current song metadata: #{e.message}"
      nil
    end
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


