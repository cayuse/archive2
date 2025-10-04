class JukeboxChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    if session_id.present?
      stream_from "jukebox_#{session_id}"
      Rails.logger.info "Client subscribed to jukebox channel: #{session_id}"
    else
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "Client unsubscribed from jukebox channel"
  end

  def receive(data)
    # Handle incoming WebSocket messages from clients
    Rails.logger.info "Received WebSocket message: #{data}"
  end
end
