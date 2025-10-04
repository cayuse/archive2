class JukeboxesController < ApplicationController
  require 'base64'
  before_action :authenticate_user!, except: [:guest]
  before_action :set_jukebox, only: [:show, :edit, :update, :destroy, :start, :pause, :resume, :end, :reset, :player, :guest]
  before_action :ensure_owner, only: [:edit, :update, :destroy, :start, :pause, :resume, :end, :reset]

  def index
    @jukeboxes = current_user.jukeboxes.order(created_at: :desc)
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
      redirect_to @jukebox, notice: 'Jukebox was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @jukebox.update(jukebox_params)
      assign_playlists_to_jukebox
      redirect_to @jukebox, notice: 'Jukebox was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @jukebox.destroy
    redirect_to jukeboxes_url, notice: 'Jukebox was successfully deleted.'
  end

  def start
    @jukebox.start!
    redirect_to @jukebox, notice: 'Jukebox started successfully.'
  end

  def pause
    @jukebox.pause!
    redirect_to @jukebox, notice: 'Jukebox paused successfully.'
  end

  def resume
    @jukebox.resume!
    redirect_to @jukebox, notice: 'Jukebox resumed successfully.'
  end

  def end
    @jukebox.end!
    redirect_to @jukebox, notice: 'Jukebox ended successfully.'
  end

  def reset
    @jukebox.reset!
    redirect_to @jukebox, notice: 'Jukebox reset successfully.'
  end

  private

  def set_jukebox
    @jukebox = Jukebox.find(params[:id])
  end

  def ensure_owner
    unless @jukebox.owner == current_user
      redirect_to jukeboxes_path, alert: 'You can only manage your own jukeboxes.'
    end
  end

  def jukebox_params
    params.require(:jukebox).permit(
      :name, :description, :location, :private, :guest_password,
      :scheduled_start, :scheduled_end, :crossfade_enabled,
      :crossfade_duration, :auto_play, :min_queue_length,
      :queue_refill_level
    )
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

  # AJB Player and Guest interfaces
  def player
    # Generate API token for the logged-in user
    Rails.logger.error "=== PLAYER ACTION DEBUG ==="
    Rails.logger.error "Current user: #{current_user&.email}"
    Rails.logger.error "About to generate token..."
    
    if current_user
      @api_token = generate_api_token_for_user(current_user)
      Rails.logger.error "Token generated: #{@api_token.present? ? 'YES' : 'NO'}"
      Rails.logger.error "Token length: #{@api_token&.length || 0}"
    else
      Rails.logger.error "No current_user found!"
      @api_token = nil
    end
    
    Rails.logger.error "Final @api_token: #{@api_token.inspect}"
    Rails.logger.error "=== END PLAYER ACTION DEBUG ==="
  end

  def guest
    # Guest interface - no authentication required, just jukebox access
    # The guest will authenticate using jukebox ID and password via JavaScript
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
        iss: 'archive-api'
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
