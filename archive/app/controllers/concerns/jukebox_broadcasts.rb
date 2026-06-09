# frozen_string_literal: true

# Helpers for pushing live jukebox updates to subscribed browsers over
# ActionCable. Clients subscribe to JukeboxChannel with the jukebox's
# session_id and receive { type: ... } messages. All broadcasts are best-effort:
# a cable failure must never break the underlying request.
module JukeboxBroadcasts
  extend ActiveSupport::Concern

  private

  def jukebox_stream(jukebox)
    "jukebox_#{jukebox.session_id}"
  end

  # Tell subscribers the queue changed; they re-fetch it through their normal
  # (authenticated) endpoint. Cheap signal, no payload.
  def broadcast_queue_update(jukebox)
    ActionCable.server.broadcast(jukebox_stream(jukebox), { type: 'queue_update' })
  rescue => e
    Rails.logger.warn "queue_update broadcast failed: #{e.message}"
  end

  # Push the current now-playing state, including enough song detail that guests
  # can render it without an extra request.
  def broadcast_playback_update(jukebox)
    song = jukebox.current_song
    ActionCable.server.broadcast(jukebox_stream(jukebox), {
      type: 'playback_status_update',
      data: {
        current_song: song && {
          id: song.id,
          title: song.title,
          artist: song.artist&.name,
          album: song.album&.title,
          duration: song.duration
        },
        position: jukebox.current_position,
        is_playing: jukebox.is_playing,
        volume: jukebox.volume,
        crossfade_duration: jukebox.crossfade_duration,
        timestamp: Time.current.iso8601
      }
    })
  rescue => e
    Rails.logger.warn "playback broadcast failed: #{e.message}"
  end
end
