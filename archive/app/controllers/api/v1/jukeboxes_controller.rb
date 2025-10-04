class Api::V1::JukeboxesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!
  before_action :set_jukebox, only: [:status, :queue, :current_song, :add_to_queue, :remove_from_queue, :move_in_queue, :playback_status, :next_song]

  def status
    render json: {
      success: true,
      jukebox: {
        id: @jukebox.id,
        name: @jukebox.name,
        session_id: @jukebox.session_id,
        status: @jukebox.status,
        crossfade_enabled: @jukebox.crossfade_enabled,
        crossfade_duration: @jukebox.crossfade_duration,
        auto_play: @jukebox.auto_play
      }
    }
  end

  def queue
    # Get queue items in the exact order specified:
    # 1. First: all 'requested' items ordered by position
    # 2. Second: all 'random' items ordered by position
    queue_items = @jukebox.ajb_queue_items
                          .includes(:song, :jukebox)
                          .queue_order
    
    render json: {
      success: true,
      queue: queue_items.map do |item|
        {
          id: item.id,
          position: item.position,
          source: item.source,
          song: {
            id: item.song.id,
            title: item.song.title,
            artist: item.song.artist&.name,
            album: item.song.album&.title,
            duration: item.song.duration,
            download_url: api_v1_song_download_url(item.song),
            stream_url: api_v1_song_stream_url(item.song)
          },
          created_at: item.created_at
        }
      end
    }
  end

  def current_song
    # Get the first item in the queue (requested items first, then random items)
    current_item = @jukebox.ajb_queue_items
                           .includes(:song)
                           .queue_order
                           .first
    
    if current_item
      render json: {
        success: true,
        song: {
          id: current_item.song.id,
          title: current_item.song.title,
          artist: current_item.song.artist&.name,
          album: current_item.song.album&.title,
          duration: current_item.song.duration,
          download_url: api_v1_song_download_url(current_item.song),
          stream_url: api_v1_song_stream_url(current_item.song)
        },
        position: current_item.position,
        source: current_item.source,
        created_at: current_item.created_at
      }
    else
      render json: {
        success: true,
        song: null
      }
    end
  end

  def add_to_queue
    song = Song.find(params[:song_id])
    source = params[:source] || 'requested' # Default to 'requested' for user requests
    
    queue_item = @jukebox.ajb_queue_items.create!(
      song: song,
      source: source
    )
    
    render json: {
      success: true,
      queue_item: {
        id: queue_item.id,
        position: queue_item.position,
        source: queue_item.source,
        song: {
          id: song.id,
          title: song.title,
          artist: song.artist&.name,
          album: song.album&.title,
          duration: song.duration
        },
        created_at: queue_item.created_at
      }
    }
  end

  def remove_from_queue
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    
    if queue_item
      queue_item.destroy
      render json: { success: true, message: 'Song removed from queue' }
    else
      render json: { success: false, message: 'Song not found in queue' }, status: 404
    end
  end

  def move_in_queue
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    new_position = params[:position].to_i
    
    if queue_item
      queue_item.update!(position: new_position)
      render json: { success: true, message: 'Song moved in queue' }
    else
      render json: { success: false, message: 'Song not found in queue' }, status: 404
    end
  end

  def playback_status
    Rails.logger.info "playback_status called with params: #{params.inspect}"
    Rails.logger.info "Current jukebox: #{@jukebox&.id} - #{@jukebox&.name}"
    
    # Update jukebox with current playback status (with safe defaults)
    update_params = { last_status_update: Time.current }
    
    # Only update fields that are provided and valid
    update_params[:current_song_id] = params[:current_song_id] if params[:current_song_id].present?
    update_params[:current_position] = params[:position].to_f if params[:position].present?
    update_params[:is_playing] = params[:is_playing] if params[:is_playing].in?([true, false])
    update_params[:volume] = params[:volume].to_f if params[:volume].present?
    # Don't update crossfade_duration unless explicitly provided - it has validation requirements
    
    Rails.logger.info "Update params: #{update_params.inspect}"
    
    begin
      @jukebox.update!(update_params)
      Rails.logger.info "Jukebox update successful"
      
      # Broadcast status update to all connected clients via WebSocket (if ActionCable is available)
      begin
        broadcast_status_update
      rescue => e
        Rails.logger.warn "WebSocket broadcast failed: #{e.message}"
        # Don't fail the request if broadcast fails
      end
      
      render json: { success: true, message: 'Playback status updated' }
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Playback status update failed: #{e.message}"
      Rails.logger.error "Validation errors: #{@jukebox.errors.full_messages}"
      render json: { success: false, message: 'Invalid playback status data', errors: @jukebox.errors.full_messages }, status: 422
    end
  end

  # New endpoint for guests to get current playback status
  def playback_info
    render json: {
      success: true,
      playback_info: {
        current_song: @jukebox.current_song_id ? {
          id: @jukebox.current_song_id,
          title: @jukebox.current_song&.title,
          artist: @jukebox.current_song&.artist&.name,
          album: @jukebox.current_song&.album&.title,
          duration: @jukebox.current_song&.duration
        } : nil,
        position: @jukebox.current_position || 0,
        is_playing: @jukebox.is_playing || false,
        volume: @jukebox.volume || 0.8,
        crossfade_duration: @jukebox.crossfade_duration || 3000,
        last_update: @jukebox.last_status_update&.iso8601
      }
    }
  end

  def ensure_min_queue_length!
    min_len = @jukebox.min_queue_length
    target = @jukebox.queue_refill_level
    return if min_len <= 0 || target <= 0

    current = @jukebox.ajb_queue_items.count
    return if current >= min_len

    need = [target - current, 0].max
    return if need <= 0

    # Get playlist IDs from jukebox's assigned playlists
    playlist_ids = @jukebox.jukebox_playlist_assignments
                           .enabled
                           .includes(:playlist)
                           .map(&:playlist_id)
    
    # If no playlists are assigned, don't add any random songs
    if playlist_ids.empty?
      Rails.logger.warn "No playlists assigned to jukebox #{@jukebox.id} - cannot add random songs"
      return
    end

    # Get songs from assigned playlists only
    playlist_song_ids = PlaylistsSong.where(playlist_id: playlist_ids).pluck(:song_id)
    
    if playlist_song_ids.empty?
      Rails.logger.warn "Assigned playlists contain no songs for jukebox #{@jukebox.id} - cannot add random songs"
      return
    end

    # Exclude recently played and already queued songs for this jukebox
    recent_ids = @jukebox.ajb_played_songs
                         .recent(50)
                         .pluck(:song_id)
    queued_ids = @jukebox.ajb_queue_items.pluck(:song_id)
    
    # Get songs that have audio files attached
    attached_ids = ActiveStorage::Attachment
                   .where(record_type: 'Song', name: 'audio_file')
                   .pluck(:record_id)
    
    # First try: songs from assigned playlists that haven't been played recently and aren't already queued
    available_songs = Song.joins(:audio_file_attachment)
                          .where(id: attached_ids)
                          .where(id: playlist_song_ids)
                          .where.not(id: recent_ids + queued_ids)
                          .order('RANDOM()')
                          .limit(need)
    
    added = 0
    available_songs.pluck(:id).each do |song_id|
      @jukebox.ajb_queue_items.create!(
        song_id: song_id,
        source: 'random'
      )
      added += 1
    end

    # If we still need more songs, allow repeats from assigned playlists
    remaining = need - added
    if remaining > 0
      Rails.logger.info "Adding #{remaining} repeated songs from assigned playlists for jukebox #{@jukebox.id} to meet minimum queue length"
      
      # Get all songs from assigned playlists (including repeats)
      repeat_songs = Song.joins(:audio_file_attachment)
                         .where(id: attached_ids)
                         .where(id: playlist_song_ids)
                         .where.not(id: queued_ids) # Still exclude already queued
                         .order('RANDOM()')
                         .limit(remaining)
      
      repeat_songs.pluck(:id).each do |song_id|
        @jukebox.ajb_queue_items.create!(
          song_id: song_id,
          source: 'random'
        )
        added += 1
      end
    end

    Rails.logger.info "Added #{added} random songs to jukebox #{@jukebox.id} queue (target: #{target}, current: #{current + added})"
  end

  # GET /api/v1/jukeboxes/:id/next_song
  # Returns the next song to play and consumes it from the queue
  def next_song
    # 0) Ensure queue is refilled to target if below minimum
    ensure_min_queue_length!

    # 1) Consume from unified ordered queue: requested first, then random; each by position
    current_item = @jukebox.ajb_queue_items
                           .includes(:song)
                           .queue_order
                           .first

    if current_item
      song = current_item.song
      source = current_item.source
      current_item.destroy! # remove from queue upon consumption
      
      # Record that this song was played
      @jukebox.ajb_played_songs.create!(
        song: song,
        played_at: Time.current,
        source: source
      )
      
      render json: {
        success: true,
        song: {
          id: song.id,
          title: song.title,
          artist: song.artist&.name,
          album: song.album&.title,
          duration: song.duration,
          download_url: download_api_v1_song_url(song),
          stream_url: stream_api_v1_song_url(song)
        },
        source: source,
        played_at: Time.current.iso8601
      }
    else
      # 2) Queue is still empty after refill -> no content
      render json: {
        success: false,
        message: 'No songs available in queue'
      }, status: :no_content
    end
  end

  private

  def authenticate_api_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { success: false, message: "Missing API token" }, status: :unauthorized
      return
    end

    begin
      # Decode from Base64
      decoded_token = Base64.urlsafe_decode64(token)
      
      # Decrypt with Rails secret key
      encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
      decrypted_payload = encryptor.decrypt_and_verify(decoded_token)
      
      # Parse JSON payload
      payload = JSON.parse(decrypted_payload)
      
      # Check if token is expired
      if payload['exp'] && Time.current.to_i > payload['exp']
        render json: { success: false, message: "API token expired" }, status: :unauthorized
        return
      end
      
      # Find the user
      @current_api_user = User.find(payload['user_id'])
      
      unless @current_api_user
        render json: { success: false, message: "Invalid API token" }, status: :unauthorized
        return
      end
      
    rescue => e
      Rails.logger.error "Token decryption error: #{e.message}"
      render json: { success: false, message: "Invalid API token" }, status: :unauthorized
      return
    end
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    # Extract token from "Bearer <token>" format
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end

  def set_jukebox
    @jukebox = Jukebox.find(params[:id])
    
    # For player endpoints (next_song, playback_status), allow owner access
    if ['next_song', 'playback_status'].include?(action_name)
      unless @jukebox.owner == @current_api_user
        render json: { success: false, message: 'Access denied' }, status: 403
      end
    else
      # For other endpoints, check owner or public access
      unless @jukebox.owner == @current_api_user || @jukebox.public?
        render json: { success: false, message: 'Access denied' }, status: 403
      end
    end
  end

  def broadcast_status_update
    # Broadcast to WebSocket clients
    ActionCable.server.broadcast(
      "jukebox_#{@jukebox.session_id}",
      {
        type: 'playback_status_update',
        data: {
          current_song_id: @jukebox.current_song_id,
          position: @jukebox.current_position,
          is_playing: @jukebox.is_playing,
          volume: @jukebox.volume,
          crossfade_duration: @jukebox.crossfade_duration,
          timestamp: Time.current.iso8601
        }
      }
    )
  end

end
