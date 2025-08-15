class Api::PlayerController < ApplicationController
  before_action :set_redis
  
  # Get comprehensive player status
  def status
    begin
      if mpd_client&.connected?
        render json: mpd_client.get_status
      else
        render json: { error: "MPD not connected", connected: false }, status: :service_unavailable
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
      if mpd_client&.connected?
        render json: mpd_client.get_current_song
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error getting current song: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get playback progress
  def progress
    begin
      if mpd_client&.connected?
        render json: mpd_client.get_progress
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error getting progress: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Get current queue/playlist
  def queue
    begin
      if mpd_client&.connected?
        render json: mpd_client.get_queue
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error getting queue: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  # Health check
  def health
    begin
      if mpd_client&.connected?
        status = mpd_client.get_status
        if status[:connected]
          render json: {
            status: 'healthy',
            mpd_connected: true,
            timestamp: Time.current.to_f
          }
        else
          render json: {
            status: 'unhealthy',
            mpd_connected: false,
            error: status[:error] || 'Unknown error',
            timestamp: Time.current.to_f
          }
        end
      else
        render json: {
          status: 'unhealthy',
          mpd_connected: false,
          error: 'MPD client not initialized',
          timestamp: Time.current.to_f
        }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error checking player health: #{e.message}"
      render json: {
        status: 'error',
        error: e.message,
        timestamp: Time.current.to_f
      }, status: :service_unavailable
    end
  end

  # Player control actions
  def play
    begin
      if mpd_client&.connected?
        result = mpd_client.resume
        render json: result
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error resuming playback: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end

  def pause
    begin
      if mpd_client&.connected?
        result = mpd_client.pause
        render json: result
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error pausing playback: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end

  def stop
    begin
      if mpd_client&.connected?
        result = mpd_client.stop
        render json: result
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error stopping playback: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end

  def next
    begin
      if mpd_client&.connected?
        result = mpd_client.next_song
        render json: result
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error skipping to next song: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end

  def previous
    begin
      if mpd_client&.connected?
        result = mpd_client.previous_song
        render json: result
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error going to previous song: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end

  private
  
  def get_volume
    begin
      if mpd_client&.connected?
        render json: mpd_client.get_volume
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error getting volume: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
    end
  end
  
  def set_volume
    begin
      if mpd_client&.connected?
        volume = params[:volume].to_i
        volume = [[0, volume].max, 100].min  # Clamp between 0-100
        
        result = mpd_client.set_volume(volume)
        render json: result
      else
        render json: { error: "MPD not connected" }, status: :service_unavailable
      end
    rescue => e
      Rails.logger.error "Error setting volume: #{e.message}"
      render json: { error: "Player API error: #{e.message}" }, status: :service_unavailable
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

  def mpd_client
    @mpd_client ||= Rails.application.config.mpd_client
  end
end
