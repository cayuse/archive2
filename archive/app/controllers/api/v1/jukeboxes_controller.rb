class Api::V1::JukeboxesController < ApplicationController
  include JukeboxBroadcasts

  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!
  before_action :set_jukebox, only: [:status, :queue, :current_song, :playback_info, :history, :add_to_queue, :remove_from_queue, :move_in_queue, :promote_in_queue, :play_next_in_queue, :playback_status, :next_song, :radio_settings]

  # List the authenticated user's own jukeboxes so player clients can offer
  # a picker instead of needing a pasted UUID.
  def index
    jukeboxes = Jukebox.where(owner: @current_api_user)
                       .includes(jukebox_playlist_assignments: :playlist)
                       .order(:name)
    render json: {
      success: true,
      jukeboxes: jukeboxes.map do |jukebox|
        {
          id: jukebox.id,
          name: jukebox.name,
          session_id: jukebox.session_id,
          status: jukebox.status,
          crossfade_enabled: jukebox.crossfade_enabled,
          crossfade_duration: jukebox.crossfade_duration,
          auto_play: jukebox.auto_play,
          queue_count: jukebox.ajb_queue_items.count,
          playlists: jukebox.jukebox_playlist_assignments.map do |assignment|
            {
              id: assignment.playlist_id,
              name: assignment.playlist&.name,
              enabled: assignment.enabled
            }
          end
        }
      end
    }
  end

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
            download_url: download_api_v1_song_url(item.song),
            stream_url: stream_api_v1_song_url(item.song)
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
          download_url: download_api_v1_song_url(current_item.song),
          stream_url: stream_api_v1_song_url(current_item.song)
        },
        position: current_item.position,
        source: current_item.source,
        created_at: current_item.created_at
      }
    else
      render json: {
        success: true,
        song: nil
      }
    end
  end

  # POST /api/v1/jukeboxes/station   [song_id]
  # The caller's personal station (created on first use). With song_id, restarts it from that song.
  def station
    unless @current_api_user.can_host_jukebox?
      return render json: { success: false, message: 'Not allowed to host a jukebox' }, status: 403
    end
    jukebox = Jukebox.station_for(@current_api_user)
    if params[:song_id].present?
      jukebox.start_from!(Song.find(params[:song_id]))
      broadcast_queue_update(jukebox)
    end
    render json: { success: true, jukebox: station_json(jukebox) }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, message: 'Song not found' }, status: 404
  end

  # PATCH /api/v1/jukeboxes/:id/radio_settings   genre=any|adjacent|strict, <dial>=-1..1, reset_steer=true
  def radio_settings
    @jukebox.update_radio_settings!(params.permit(:genre, :reset_steer, *SongAudioFeature::DIALS))
    broadcast_queue_update(@jukebox)
    render json: { success: true, jukebox: station_json(@jukebox) }
  end

  def add_to_queue
    song = Song.find(params[:song_id])
    source = params[:source].presence_in(%w[requested random]) || 'requested'

    if @jukebox.ajb_queue_items.exists?(song_id: song.id)
      return render json: { success: false, message: 'Song is already in the queue' }, status: 409
    end

    @jukebox.retune! if source == 'requested'   # radio: the request re-aims the station
    queue_item = @jukebox.ajb_queue_items.create!(song: song, source: source)
    broadcast_queue_update(@jukebox)

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
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, message: 'Song not found' }, status: 404
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: 'Could not add song to queue', errors: e.record.errors.full_messages }, status: 422
  end

  def remove_from_queue
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    
    if queue_item
      queue_item.destroy
      broadcast_queue_update(@jukebox)
      render json: { success: true, message: 'Song removed from queue' }
    else
      render json: { success: false, message: 'Song not found in queue' }, status: 404
    end
  end

  def move_in_queue
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    return render json: { success: false, message: 'Song not found in queue' }, status: 404 unless queue_item

    new_position = params[:position].to_i
    if new_position <= 0
      return render json: { success: false, message: 'Position must be a positive number' }, status: 422
    end

    queue_item.update!(position: new_position)
    broadcast_queue_update(@jukebox)
    render json: { success: true, message: 'Song moved in queue' }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: 'Could not move song', errors: e.record.errors.full_messages }, status: 422
  end

  # Promote a random (auto-filled) item into the requested queue so it jumps
  # ahead of the remaining random songs.
  def promote_in_queue
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    return render json: { success: false, message: 'Song not found in queue' }, status: 404 unless queue_item

    queue_item.update!(source: 'requested')
    broadcast_queue_update(@jukebox)
    render json: { success: true, message: 'Song promoted to the request queue' }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: 'Could not promote song', errors: e.record.errors.full_messages }, status: 422
  end

  # Host party trick: bump a song to the very top so it plays next. Make it a
  # requested item at position 1, shifting everything else down, atomically.
  def play_next_in_queue
    queue_item = @jukebox.ajb_queue_items.find_by(song_id: params[:song_id])
    return render json: { success: false, message: 'Song not found in queue' }, status: 404 unless queue_item

    @jukebox.with_lock do
      @jukebox.ajb_queue_items.where.not(id: queue_item.id).update_all('position = position + 1')
      queue_item.update!(source: 'requested', position: 1)
    end
    broadcast_queue_update(@jukebox)
    render json: { success: true, message: 'Song will play next' }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: 'Could not move song', errors: e.record.errors.full_messages }, status: 422
  end

  def playback_status
    # Update jukebox with current playback status (with safe defaults)
    update_params = { last_status_update: Time.current }

    # Only update fields that are provided and valid
    if params[:current_song_id].present? && Song.exists?(params[:current_song_id])
      update_params[:current_song_id] = params[:current_song_id]
    end
    update_params[:current_position] = params[:position].to_f if params[:position].present?
    update_params[:is_playing] = params[:is_playing] if params[:is_playing].in?([true, false])
    update_params[:volume] = params[:volume].to_f if params[:volume].present?
    # Don't update crossfade_duration unless explicitly provided - it has validation requirements

    begin
      @jukebox.update!(update_params)
      Rails.logger.info "Jukebox update successful"

      # Diagnostic breadcrumb (NOT persisted, no schema change): lets us watch
      # what a locked phone's player is doing at track edges via the server log.
      # Grep "[AJB diag]". `event` tags what triggered this heartbeat
      # (heartbeat/track_end/advance_start/advance_done/stall_*/play_blocked/...).
      if params[:event].present? || params[:diag].present?
        diag = params[:diag]
        diag_json = diag.respond_to?(:to_unsafe_h) ? diag.to_unsafe_h.to_json : diag.to_json
        Rails.logger.info("[AJB diag] jukebox=#{@jukebox.id} event=#{params[:event]} diag=#{diag_json}")
      end

      # Push the new now-playing state to subscribed guests.
      broadcast_playback_update(@jukebox)

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

  # GET /api/v1/jukeboxes/:id/history?page=&per_page=
  # Paginated play history for THIS jukebox (most recent first). Scoped by
  # jukebox so multiple jukeboxes keep independent histories.
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

  def ensure_min_queue_length!
    min_len = @jukebox.min_queue_length
    target = @jukebox.queue_refill_level
    return if min_len <= 0 || target <= 0

    current = @jukebox.ajb_queue_items.count
    return if current >= min_len

    need = [target - current, 0].max
    return if need <= 0

    if @jukebox.fill_mode == 'radio'
      need -= add_radio_songs!(need)
      return if need <= 0
    end

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
  # Radio auto-fill: queue songs that sound like the latest request (or the last song in line).
  # Stays inside the assigned playlists when there are any, otherwise uses the whole library.
  # Returns how many were added; the caller tops up the rest at random.
  def add_radio_songs!(need)
    seed_id = @jukebox.ajb_queue_items.requested.order(position: :desc).pick(:song_id) ||
              @jukebox.ajb_played_songs.where(source: 'requested').order(played_at: :desc).pick(:song_id) ||
              @jukebox.ajb_queue_items.order(position: :desc).pick(:song_id) ||
              @jukebox.ajb_played_songs.order(played_at: :desc).pick(:song_id)
    seed = seed_id && Song.find_by(id: seed_id)
    return 0 unless seed

    playlist_ids = @jukebox.jukebox_playlist_assignments.enabled.pluck(:playlist_id)
    allowed = playlist_ids.any? ? PlaylistsSong.where(playlist_id: playlist_ids).pluck(:song_id) : nil
    exclude = @jukebox.ajb_played_songs.recent(50).pluck(:song_id) + @jukebox.ajb_queue_items.pluck(:song_id)

    # A tight genre setting can run dry (small genres have few sound-alikes). Rather than let the
    # music stop, loosen the genre limit step by step for this top-up only.
    added = 0
    modes = [ @jukebox.radio_genre_mode, "adjacent", "any" ].uniq
    modes = modes.drop_while { |m| m != @jukebox.radio_genre_mode }
    modes.each do |mode|
      break if added >= need
      SongRadio.new(seed: seed, exclude_ids: exclude, allowed_ids: allowed, user: @jukebox.owner,
                    steer: @jukebox.radio_steer, genre_mode: mode).next_songs(need - added).each do |song|
        next unless @jukebox.ajb_queue_items.create(song_id: song.id, source: 'random').persisted?
        added += 1
        exclude << song.id
      end
    end

    # Last resort for a station with no playlists (seed never analysed, or everything nearby was
    # played recently): any analysed music, so the stream keeps going.
    if added < need && allowed.nil?
      Song.joins(:audio_feature).where("song_audio_features.speech < ?", SongRadio::SPEECH_CUTOFF)
          .where.not(id: exclude + [ seed.id ]).order(Arel.sql("RANDOM()")).limit(need - added).pluck(:id).each do |song_id|
        added += 1 if @jukebox.ajb_queue_items.create(song_id: song_id, source: 'random').persisted?
      end
    end
    Rails.logger.info "Radio fill: added #{added} of #{need} songs to jukebox #{@jukebox.id} from seed #{seed.id}"
    added
  rescue => e
    Rails.logger.error "Radio fill failed for jukebox #{@jukebox.id}: #{e.message}"
    0
  end
  private :add_radio_songs!

  # Not an action — only called internally by next_song.
  private :ensure_min_queue_length!

  # GET /api/v1/jukeboxes/:id/next_song
  # Returns the next song to play and consumes it from the queue
  def next_song
    # 0) Ensure queue is refilled to target if below minimum
    ensure_min_queue_length!

    # 1) Consume the head of the queue atomically so two concurrent player polls
    #    can't both grab (or double-destroy) the same item.
    song = source = nil
    @jukebox.with_lock do
      current_item = @jukebox.ajb_queue_items
                             .includes(:song)
                             .queue_order
                             .first
      if current_item
        song = current_item.song
        source = current_item.source
        current_item.destroy! # remove from queue upon consumption
        @jukebox.ajb_played_songs.create!(
          song: song,
          played_at: Time.current,
          source: source
        )
      end
    end

    if song
      broadcast_queue_update(@jukebox)
      render json: {
        success: true,
        song: {
          id: song.id,
          title: song.title,
          artist: song.artist&.name,
          album: song.album&.title,
          duration: song.duration,
          download_url: download_api_v1_song_url(song),
          stream_url: stream_api_v1_song_url(song),
          # tokenized, no-login link for players that cannot send headers (OwnTone / AirPlay)
          play_url: public_song_url(token: SongPlayToken.generate(song.id, expires_in: 12.hours))
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

  # Read-only actions may be reached on a public jukebox by any authenticated API
  # user; anything that mutates the jukebox or its queue is owner-only. (Rendering
  # in a before_action halts the action chain.)
  READ_ONLY_ACTIONS = %w[status queue current_song playback_info history].freeze

  def station_json(jukebox)
    {
      id: jukebox.id, name: jukebox.name, session_id: jukebox.session_id, fill_mode: jukebox.fill_mode,
      station: jukebox.station?, guest_password: jukebox.guest_password,
      radio: { genre: jukebox.radio_genre_mode, steer: jukebox.radio_steer },
      queue_length: jukebox.ajb_queue_items.count
    }
  end

  def set_jukebox
    @jukebox = Jukebox.find(params[:id])

    owner = @jukebox.owner == @current_api_user
    public_read = READ_ONLY_ACTIONS.include?(action_name) && @jukebox.public?

    unless owner || public_read
      render json: { success: false, message: 'Access denied' }, status: 403
    end
  end

end
