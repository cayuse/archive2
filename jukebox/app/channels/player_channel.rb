class PlayerChannel < ApplicationCable::Channel
  def subscribed
    stream_from "player_channel"
    Rails.logger.info "PlayerChannel: Client subscribed"
  end

  def unsubscribed
    Rails.logger.info "PlayerChannel: Client unsubscribed"
  end

  def receive(data)
    Rails.logger.info "PlayerChannel: Received data: #{data}"
    
    # Handle incoming commands from the client
    case data['action']
    when 'play'
      handle_play
    when 'pause'
      handle_pause
    when 'stop'
      handle_stop
    when 'next'
      handle_next
    when 'previous'
      handle_previous
    when 'volume'
      handle_volume(data['volume'])
    when 'status'
      broadcast_current_status
    else
      Rails.logger.warn "PlayerChannel: Unknown action: #{data['action']}"
    end
  end

  private

  def handle_play
    return unless mpd_client&.connected?
    
    begin
      result = mpd_client.resume
      broadcast_status_update(result)
    rescue => e
      Rails.logger.error "Error handling play: #{e.message}"
      broadcast_error("Failed to play: #{e.message}")
    end
  end

  def handle_pause
    return unless mpd_client&.connected?
    
    begin
      result = mpd_client.pause
      broadcast_status_update(result)
    rescue => e
      Rails.logger.error "Error handling pause: #{e.message}"
      broadcast_error("Failed to pause: #{e.message}")
    end
  end

  def handle_stop
    return unless mpd_client&.connected?
    
    begin
      result = mpd_client.stop
      broadcast_status_update(result)
    rescue => e
      Rails.logger.error "Error handling stop: #{e.message}"
      broadcast_error("Failed to stop: #{e.message}")
    end
  end

  def handle_next
    return unless mpd_client&.connected?
    
    begin
      result = mpd_client.next_song
      broadcast_status_update(result)
    rescue => e
      Rails.logger.error "Error handling next: #{e.message}"
      broadcast_error("Failed to skip to next song: #{e.message}")
    end
  end

  def handle_previous
    return unless mpd_client&.connected?
    
    begin
      result = mpd_client.previous_song
      broadcast_status_update(result)
    rescue => e
      Rails.logger.error "Error handling previous: #{e.message}"
      broadcast_error("Failed to go to previous song: #{e.message}")
    end
  end

  def handle_volume(volume)
    return unless mpd_client&.connected?
    
    begin
      volume = volume.to_i
      result = mpd_client.set_volume(volume)
      broadcast_status_update(result)
    rescue => e
      Rails.logger.error "Error handling volume change: #{e.message}"
      broadcast_error("Failed to change volume: #{e.message}")
    end
  end

  def broadcast_current_status
    return unless mpd_client&.connected?
    
    begin
      status = mpd_client.get_status
      ActionCable.server.broadcast("player_channel", {
        type: 'status_update',
        data: status,
        timestamp: Time.current.to_f
      })
    rescue => e
      Rails.logger.error "Error broadcasting current status: #{e.message}"
      broadcast_error("Failed to get current status: #{e.message}")
    end
  end

  def broadcast_status_update(result)
    ActionCable.server.broadcast("player_channel", {
      type: 'command_result',
      data: result,
      timestamp: Time.current.to_f
    })
  end

  def broadcast_error(message)
    ActionCable.server.broadcast("player_channel", {
      type: 'error',
      message: message,
      timestamp: Time.current.to_f
    })
  end

  def mpd_client
    @mpd_client ||= Rails.application.config.mpd_client
  end
end
