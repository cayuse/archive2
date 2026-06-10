class JukeboxChannel < ApplicationCable::Channel
  def subscribed
    # Key the stream on the jukebox's immutable UUID, not the editable session_id
    # slug — a renamed/edited slug would silently orphan connected clients.
    jukebox_id = params[:jukebox_id].to_s
    if jukebox_id.present?
      stream_from "jukebox_#{jukebox_id}"
      Rails.logger.info "Client subscribed to jukebox channel: #{jukebox_id}"
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
