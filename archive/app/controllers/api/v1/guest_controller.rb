class Api::V1::GuestController < ApplicationController
  skip_before_action :verify_authenticity_token
  # before_action :authenticate_guest!  # Temporarily disabled for debugging
  # before_action :set_jukebox  # Temporarily disabled
  # before_action :ensure_jukebox_active!  # Temporarily disabled for debugging

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
      
      # Check if song is already in queue
      existing_item = @jukebox.ajb_queue_items.find_by(song: song)
      if existing_item
        render json: { 
          success: false, 
          message: 'Song is already in the queue' 
        }, status: 409
        return
      end
      
      # Add song to queue as requested
      queue_item = @jukebox.ajb_queue_items.create!(
        song: song,
        source: 'requested'
      )
      
      render json: {
        success: true,
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

  private

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

    # Check if jukebox has a password
    if jukebox.has_password?
      if password.blank?
        render json: { success: false, message: 'Password required for this jukebox' }, status: 401
        return
      end

      # Verify password (plain text comparison)
      unless jukebox.guest_password == password
        render json: { success: false, message: 'Invalid password' }, status: 401
        return
      end
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
    # Only allow access if jukebox is active or paused (not inactive or ended)
    unless @jukebox.status.in?(['active', 'paused'])
      render json: { 
        success: false, 
        message: 'Jukebox is not currently active. Please wait for the host to start the jukebox.' 
      }, status: 403
      return
    end
  end
end
