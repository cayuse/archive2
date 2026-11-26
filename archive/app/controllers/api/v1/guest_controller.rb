class Api::V1::GuestController < ApplicationController
  include JukeboxBroadcasts

  skip_before_action :verify_authenticity_token
  before_action :authenticate_guest!   # Enforce jukebox guest-password auth
  before_action :set_jukebox           # Load @jukebox (404s if missing)
  before_action :ensure_jukebox_active! # Only active/paused jukeboxes are reachable
  before_action :require_guest_admin!, only: [:promote_song, :remove_song, :player_command]

  PLAYER_COMMANDS = %w[play pause skip].freeze

  # GET /api/v1/guest/:jukebox_id/test
  def test
    jukebox = Jukebox.find_by(id: params[:jukebox_id])
    render json: { 
      success: true, 
      message: 'Test endpoint working', 
      jukebox_id: params[:jukebox_id], 
      jukebox_found: jukebox.present?,
      before_action_jukebox: @jukebox.present?
    }
  end

  # GET /api/v1/guest/:jukebox_id/status
  # Returns basic jukebox status for guests (read-only)
  def status
    Rails.logger.info "status method called with jukebox_id: #{params[:jukebox_id]}"
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    Rails.logger.info "Jukebox found: #{@jukebox.present?}"
    unless @jukebox
      Rails.logger.info "Jukebox not found, rendering 404"
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
    render json: {
      success: true,
      jukebox: {
        id: @jukebox.id,
        name: @jukebox.name,
        session_id: @jukebox.session_id,
        status: @jukebox.status,
        role: @guest_role,
        current_song_id: @jukebox.current_song_id,
        current_position: @jukebox.current_position,
        is_playing: @jukebox.is_playing,
        volume: @jukebox.volume,
        started_at: @jukebox.started_at&.iso8601,
        current_duration: @jukebox.current_duration
      }
    }
  end

  # GET /api/v1/guest/:jukebox_id/current_song
  # Returns current song information for guests
  def current_song
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    unless @jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
    
    if @jukebox.current_song
      render json: {
        success: true,
        song: {
          id: @jukebox.current_song.id,
          title: @jukebox.current_song.title,
          artist: @jukebox.current_song.artist&.name,
          album: @jukebox.current_song.album&.title,
          duration: @jukebox.current_song.duration,
          # Note: No download/stream URLs for guests - they can only see what's playing
        },
        position: @jukebox.current_position,
        is_playing: @jukebox.is_playing,
        started_at: @jukebox.started_at&.iso8601
      }
    else
      render json: {
        success: true,
        song: nil,
        position: 0,
        is_playing: false,
        message: 'No song currently playing'
      }
    end
  end

  # GET /api/v1/guest/:jukebox_id/queue
  # Returns current queue for guests (read-only, no song details)
  def queue
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    unless @jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
    
    queue_items = @jukebox.ajb_queue_items
                          .includes(:song)
                          .queue_order
                          .limit(50) # Limit to next 50 songs for guests

    render json: {
      success: true,
      queue: queue_items.map do |item|
        {
          position: item.position,
          source: item.source,
          song: {
            id: item.song.id,
            title: item.song.title,
            artist: item.song.artist&.name,
            duration: item.song.duration
            # Note: No download/stream URLs for guests
          }
        }
      end,
      total_count: @jukebox.ajb_queue_items.count
    }
  end

  # GET /api/v1/guest/:jukebox_id/playback_info
  # Returns current playback information for guests
  def playback_info
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    unless @jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
    
    render json: {
      success: true,
      playback: {
        current_song: @jukebox.current_song ? {
          id: @jukebox.current_song.id,
          title: @jukebox.current_song.title,
          artist: @jukebox.current_song.artist&.name,
          album: @jukebox.current_song.album&.title,
          duration: @jukebox.current_song.duration
        } : nil,
        position: @jukebox.current_position,
        is_playing: @jukebox.is_playing,
        volume: @jukebox.volume,
        started_at: @jukebox.started_at&.iso8601,
        current_duration: @jukebox.current_duration,
        crossfade_enabled: @jukebox.crossfade_enabled,
        crossfade_duration: @jukebox.crossfade_duration
      }
    }
  end

  # GET /api/v1/guest/:jukebox_id/history?page=&per_page=
  # Paginated play history for this jukebox (most recent first).
  def history
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 25).to_i.clamp(1, 100)
    played = AjbPlayedSong.history_for(@jukebox).page(page).per(per_page)
    render json: {
      success: true,
      history: played.map(&:history_payload),
      pagination: {
        current_page: played.current_page,
        total_pages: played.total_pages,
        total_count: played.total_count,
        per_page: per_page,
        has_more: played.next_page.present?
      }
    }
  end

  # GET /api/v1/guest/:jukebox_id/search_songs
  def search_songs
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    unless @jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
    
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    
    # Use the same search logic as the main songs controller
    songs = Song.includes(:artist, :album, :genre)
                .order(created_at: :desc)
    
    if query.present?
      # Multi-term search: each term must exist somewhere (AND logic between terms)
      # "strait run" finds songs where ANY field contains "strait" AND ANY field contains "run"
      # More terms = more specific/fewer results
      
      # Split query into individual terms, removing empty strings
      terms = query.strip.split(/\s+/).reject(&:blank?)
      
      unless terms.empty?
        # Build a condition for each term that searches across all fields
        conditions = terms.map do |term|
          sanitized = ActiveRecord::Base.sanitize_sql_like(term)
          "(songs.title ILIKE ? OR artists.name ILIKE ? OR albums.title ILIKE ? OR genres.name ILIKE ?)"
        end
        
        # All terms must be found (AND logic between terms)
        where_clause = conditions.join(" AND ")
        
        # Flatten the parameters array (4 params per term: title, artist, album, genre)
        params_array = terms.flat_map { |term| 
          sanitized = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
          [sanitized, sanitized, sanitized, sanitized] 
        }
        
        songs = songs.joins("LEFT JOIN artists ON songs.artist_id = artists.id")
                     .joins("LEFT JOIN albums ON songs.album_id = albums.id")
                     .joins("LEFT JOIN genres ON songs.genre_id = genres.id")
                     .where(where_clause, *params_array)
                     .distinct
      end
    end
    
    # Paginate results
    songs = songs.page(page).per(per_page)
    
    render json: {
      success: true,
      songs: songs.map do |song|
        {
          id: song.id,
          title: song.title,
          artist: song.artist&.name,
          album: song.album&.title,
          genre: song.genre&.name,
          duration: song.duration,
          # Note: No download/stream URLs for guests
        }
      end,
      pagination: {
        current_page: songs.current_page,
        total_pages: songs.total_pages,
        total_count: songs.total_count,
        per_page: songs.limit_value,
        has_more: songs.next_page.present?
      }
    }
  end
  
  # POST /api/v1/guest/:jukebox_id/request_song
  def request_song
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    unless @jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
    
    begin
      song = Song.find(params[:song_id])
      
      # Already queued is a no-op, not an error. Only an admin-code guest may
      # reorder the queue, so only their request bumps an auto-filled song.
      existing_item = @jukebox.ajb_queue_items.find_by(song: song)
      if existing_item
        if existing_item.source == 'requested'
          render json: { success: true, outcome: 'already_requested', message: 'Song is already requested' }
        elsif @guest_role != :admin
          render json: { success: true, outcome: 'already_queued', message: 'Song is already in the queue' }
        else
          existing_item.update!(source: 'requested')
          broadcast_queue_update(@jukebox)
          render json: { success: true, outcome: 'bumped', message: 'Song bumped up the queue' }
        end
        return
      end
      
      # Add song to queue as requested
      @jukebox.retune! if @jukebox.requests_steer?   # a request re-aims a personal station, not a party
      queue_item = @jukebox.ajb_queue_items.create!(
        song: song,
        source: 'requested'
      )
      broadcast_queue_update(@jukebox)

      render json: {
        success: true,
        outcome: 'added',
        message: 'Song requested successfully',
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
          }
        }
      }
    rescue ActiveRecord::RecordNotFound
      render json: { 
        success: false, 
        message: 'Song not found' 
      }, status: 404
    rescue ActiveRecord::RecordInvalid => e
      render json: { 
        success: false, 
        message: 'Failed to add song to queue', 
        errors: e.record.errors.full_messages 
      }, status: 422
    end
  end

  # POST /api/v1/guest/:jukebox_id/promote_song
  # Admin-code guests can promote a random (auto-filled) song into the request
  # queue so it plays sooner.
  def promote_song
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    unless queue_item
      return render json: { success: false, message: 'Song is not in the queue' }, status: 404
    end

    queue_item.update!(source: 'requested')
    broadcast_queue_update(@jukebox)
    render json: { success: true, message: 'Song promoted' }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: 'Could not promote song', errors: e.record.errors.full_messages }, status: 422
  end

  # DELETE /api/v1/guest/:jukebox_id/queue/:song_id (admin code only)
  def remove_song
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    unless queue_item
      return render json: { success: false, message: 'Song is not in the queue' }, status: 404
    end

    queue_item.destroy
    broadcast_queue_update(@jukebox)
    render json: { success: true, message: 'Song removed' }
  end

  # POST /api/v1/guest/:jukebox_id/player_command (admin code only)
  # The music plays in the host's browser, so this relays the command to it
  # over the jukebox channel; the player reports the new state on its heartbeat.
  def player_command
    command = params[:command].to_s
    unless PLAYER_COMMANDS.include?(command)
      return render json: { success: false, message: 'Unknown command' }, status: 422
    end

    if @jukebox.server_playback?
      @jukebox.transport!(command)          # the node's daemon is the player
      broadcast_playback_update(@jukebox)
    else
      broadcast_player_command(@jukebox, command)
    end
    render json: { success: true, command: command }
  end

  private

  def require_guest_admin!
    return if @guest_role == :admin
    render json: { success: false, message: 'Admin code required' }, status: 403
  end

  def authenticate_guest!
    jukebox_id = params[:jukebox_id]
    password = params[:password]

    if jukebox_id.blank?
      render json: { success: false, message: 'Jukebox ID required' }, status: 400
      return
    end

    # Find jukebox
    jukebox = Jukebox.find_by(id: jukebox_id)
    unless jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end

    if password.blank?
      render json: { success: false, message: 'Password required for this jukebox' }, status: 401
      return
    end

    # The code decides the role: admin code -> :admin, guest code -> :guest.
    @guest_role = jukebox.guest_role_for(password)
    unless @guest_role
      render json: { success: false, message: 'Invalid password' }, status: 401
      return
    end

    # Store authenticated jukebox for use in other methods
    @authenticated_jukebox = jukebox
  end

  def set_jukebox
    Rails.logger.info "set_jukebox called with jukebox_id: #{params[:jukebox_id]}"
    @jukebox = Jukebox.find_by(id: params[:jukebox_id])
    Rails.logger.info "Jukebox found: #{@jukebox.present?}"
    unless @jukebox
      render json: { success: false, message: 'Jukebox not found' }, status: 404
      return
    end
  end

  def ensure_jukebox_active!
    # The jukebox is reachable to guests only while a player is actively running
    # (presence-driven). No live player -> nothing to join.
    unless @jukebox.live?
      render json: {
        success: false,
        message: 'This jukebox is not running right now. Ask the host to open the player.'
      }, status: 403
      return
    end
  end
end
