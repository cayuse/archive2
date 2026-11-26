class JukeboxesController < ApplicationController
  require "base64"
  before_action :authenticate_user!, except: [ :guest, :guest_short ]
  before_action :require_host!, except: [ :guest, :guest_short ]
  before_action :set_jukebox, only: [ :show, :edit, :update, :destroy, :player, :guest, :server_playback ]
  # show and player are owner-only too: they display the guest and admin codes and mint an API token.
  before_action :ensure_owner, only: [ :show, :edit, :update, :destroy, :player, :server_playback ]

  def index
    # stations (personal radio) have their own page; this one lists party jukeboxes
    @jukeboxes = current_user.jukeboxes.where.not("session_id LIKE ?", "#{Jukebox::STATION_PREFIX}%").order(created_at: :desc)
  end

  def show
    @jukebox_playlist_assignments = @jukebox.jukebox_playlist_assignments.includes(:playlist).order(:weight, :created_at)
    @available_playlists = Playlist.publicly_visible.where.not(id: @jukebox.playlist_ids)
  end

  def new
    @jukebox = current_user.jukeboxes.build
  end

  def edit
  end

  def create
    @jukebox = current_user.jukeboxes.build(jukebox_params)

    if @jukebox.save
      assign_playlists_to_jukebox
      save_radio_options
      redirect_to @jukebox, notice: "Jukebox was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @jukebox.update(jukebox_params)
      assign_playlists_to_jukebox
      save_radio_options
      redirect_to @jukebox, notice: "Jukebox was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @jukebox.destroy
    redirect_to jukeboxes_url, notice: "Jukebox was successfully deleted."
  end

  private

  def set_jukebox
    @jukebox = Jukebox.find(params[:id])
  end

  def ensure_owner
    unless @jukebox.owner == current_user
      redirect_to jukeboxes_path, alert: "You can only manage your own jukeboxes."
    end
  end

  # Hosting a jukebox is a moderator+ capability (matches Upload/Maintenance).
  # Change this single check to adjust who can host (e.g. allow all users, or
  # require admin, or swap in a per-user capability flag).
  def require_host!
    unless current_user&.can_host_jukebox?
      redirect_to root_path, alert: "Hosting a jukebox requires the DJ, moderator, or admin role."
    end
  end

  def jukebox_params
    params.require(:jukebox).permit(
      :name, :description, :location, :session_id, :guest_password, :admin_password,
      :scheduled_start, :scheduled_end, :crossfade_enabled,
      :crossfade_duration, :auto_play, :min_queue_length,
      :queue_refill_level, :fill_mode
    )
  end

  # Radio options kept in radio_settings rather than in columns of their own.
  def save_radio_options
    bind_station
    value = params.dig(:jukebox, :requests_steer)
    return if value.nil? || @jukebox.requests_steer? == (value.to_s == "1")
    @jukebox.write_radio_settings!(@jukebox.radio_settings.merge("requests_steer" => value.to_s == "1"))
  end

  # A party jukebox can play from one of the owner's stations (its seeds, tuning and taste)
  # instead of keeping a private radio of its own. Blank = its own.
  def bind_station
    return if @jukebox.station? || !params[:jukebox].key?(:station_id)
    chosen = Station.for_user(current_user).find_by(id: params[:jukebox][:station_id].presence)
    return if chosen&.id == @jukebox.station_id || (chosen.nil? && (@jukebox.station.nil? || @jukebox.station.implicit?))
    old = @jukebox.station
    @jukebox.update!(station: chosen)
    old.destroy if old&.implicit?
    @jukebox.retune!
  end

  def assign_playlists_to_jukebox
    playlist_ids = params[:jukebox][:playlist_ids] || []

    # Remove existing assignments
    @jukebox.jukebox_playlist_assignments.destroy_all

    # Add new assignments (only if playlist_ids are provided)
    if playlist_ids.present?
      playlist_ids.each_with_index do |playlist_id, index|
        next if playlist_id.blank?
        @jukebox.jukebox_playlist_assignments.create!(
          playlist_id: playlist_id,
          weight: index + 1,
          enabled: true
        )
      end
    end
  end

  # The Player/Guest/short-guest pages are public-facing actions reached via
  # routes — declare them public so Ruby's `private` above never swallows them
  # (Rails raises ActionNotFound for a private method just like a missing one).
  public

  # Toggle whether this jukebox is driven by the node's server-side player task.
  # Owner-only (ensure_owner) and only where local playback is available to this
  # user here (authorize_local_playback!).
  def server_playback
    authorize_local_playback!
    return if performed?
    if ActiveModel::Type::Boolean.new.cast(params[:server_playback])
      # play=1 (the "Play on speakers" buttons): start playing and go straight to the remote.
      if params[:play].present?
        @jukebox.start_server_playback!(transport: "play")
        return redirect_to player_jukebox_path(@jukebox)
      end
      @jukebox.start_server_playback!
    elsif @jukebox.server_playback?
      @jukebox.end_server_playback!
    end
    redirect_to @jukebox, notice: @jukebox.server_playback? ?
      "This jukebox now plays on the archive's speakers. The player page is a remote control." :
      "This jukebox now plays in the host's browser."
  end

  # AJB Player and Guest interfaces
  def player
    # Generate a short-lived API token for the logged-in host's browser player.
    @api_token = current_user ? generate_api_token_for_user(current_user) : nil
    # Server-played jukeboxes: the node's hidden task is the player, so the page
    # is a passive remote (status + a link to the local controls), never Howler.
    render :controller if @jukebox.server_playback?
  end

  def guest
    # Guest interface - no authentication required, just jukebox access
    # The guest will authenticate using jukebox ID and password via JavaScript
  end

  # Pretty short URL (/j/<slug>): resolve the slug to its jukebox and serve the
  # same guest page. Everything downstream still keys on @jukebox.id (the UUID).
  def guest_short
    @jukebox = Jukebox.find_by(session_id: params[:code].to_s.downcase.strip)
    return render plain: "Jukebox not found.", status: :not_found unless @jukebox
    render :guest
  end

  private

  def generate_api_token_for_user(user)
    begin
      # Create payload with user info and expiration (2 days)
      payload = {
        user_id: user.id,
        email: user.email,
        role: user.role,
        exp: 2.days.from_now.to_i,
        iat: Time.current.to_i,
        iss: "archive-api"
      }

      # Convert to JSON and encrypt with Rails secret key
      json_payload = payload.to_json
      encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
      encrypted_token = encryptor.encrypt_and_sign(json_payload)

      # Base64 encode for URL safety
      Base64.urlsafe_encode64(encrypted_token)
    rescue => e
      Rails.logger.error "Error generating API token: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end
end
