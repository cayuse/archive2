class Api::JukeboxController < ApplicationController
  before_action :set_jukebox_service
  
  # GET /api/jukebox/status
  def status
    render json: @jukebox_service.get_player_status
  end
  
  # GET /api/jukebox/health
  def health
    render json: @jukebox_service.get_system_health
  end
  
  # POST /api/jukebox/queue
  def add_to_queue
    song_id = params[:song_id]
    user = current_user if respond_to?(:current_user)
    
    if @jukebox_service.add_to_queue(song_id, user)
      render json: { success: true, message: 'Song added to queue' }
    else
      render json: { success: false, message: 'Failed to add song to queue' }, status: :unprocessable_entity
    end
  end
  
  # DELETE /api/jukebox/queue/:position
  def remove_from_queue
    position = params[:position].to_i
    
    if @jukebox_service.remove_from_queue(position)
      render json: { success: true, message: 'Song removed from queue' }
    else
      render json: { success: false, message: 'Failed to remove song from queue' }, status: :not_found
    end
  end
  
  # DELETE /api/jukebox/queue
  def clear_queue
    @jukebox_service.clear_queue
    render json: { success: true, message: 'Queue cleared' }
  end
  
  # GET /api/jukebox/queue
  def get_queue
    render json: @jukebox_service.get_queue
  end
  
  # POST /api/jukebox/control
  def control
    action = params[:action]
    
    case action
    when 'play'
      if @jukebox_service.play
        message = 'Playback started'
      else
        render json: { 
          success: false, 
          message: 'Cannot start playback - no content available',
          status: @jukebox_service.get_player_status
        }, status: :unprocessable_entity
        return
      end
    when 'pause'
      @jukebox_service.pause
      message = 'Playback paused'
    when 'stop'
      @jukebox_service.stop
      message = 'Playback stopped'
    when 'next'
      @jukebox_service.next_song
      message = 'Next song'
    when 'previous'
      @jukebox_service.previous_song
      message = 'Previous song'
    when 'volume'
      volume = params[:volume].to_i
      @jukebox_service.set_volume(volume)
      message = "Volume set to #{volume}%"
    when 'crossfade'
      duration = params[:duration].to_i
      @jukebox_service.set_crossfade(duration)
      message = "Crossfade set to #{duration} seconds"
    when 'refill'
      @jukebox_service.populate_random_pool
      message = 'Random pool refilled'
    else
      render json: { success: false, message: "Unknown action: #{action}" }, status: :bad_request
      return
    end
    
    render json: { success: true, message: message }
  end
  
  # GET /api/jukebox/cached_songs
  def cached_songs
    render json: @jukebox_service.get_cached_songs
  end
  
  private
  
  def set_jukebox_service
    @jukebox_service = JukeboxService.new
  end
end 