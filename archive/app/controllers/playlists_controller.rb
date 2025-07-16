class PlaylistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_playlist, only: [:show, :update, :reorder, :add_songs, :remove_songs]
  
  def index
    # User's own playlists
    @user_playlists = current_user.playlists
                                 .includes(:songs)
                                 .order(:name)
                                 .page(params[:user_page])
                                 .per(params[:per_page] || 20)
    
    # Public playlists from other users
    @shared_playlists = Playlist.publicly_visible
                                .where.not(user: current_user)
                                .includes(:songs, :user)
                                .order(:name)
                                .page(params[:shared_page])
                                .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @playlist.songs.includes(:artist, :album, :genre).order(:position, :title)
  end
  
  def create
    @playlist = current_user.playlists.build(playlist_params)
    
    if @playlist.save
      # Add songs if song_ids are provided
      if params[:song_ids].present?
        song_ids = params[:song_ids]
        # Start position at 1,000,000 to add new songs at the end
        next_position = @playlist.playlists_songs.maximum(:position) || 1_000_000
        
        song_ids.each_with_index do |song_id, index|
          @playlist.playlists_songs.create!(song_id: song_id, position: next_position + index)
        end
      end
      
      if request.xhr?
        render json: { 
          success: true, 
          message: "Playlist created successfully with #{params[:song_ids]&.length || 0} songs.",
          playlist_id: @playlist.id,
          playlist_name: @playlist.name,
          redirect_url: playlist_path(@playlist)
        }
      else
        redirect_to @playlist, notice: 'Playlist created successfully.'
      end
    else
      if request.xhr?
        render json: { error: 'Failed to create playlist.' }, status: :unprocessable_entity
      else
        redirect_to playlists_path, alert: 'Failed to create playlist.'
      end
    end
  end
  
  def update
    if @playlist.owned_by?(current_user) && @playlist.update(playlist_params)
      redirect_to @playlist, notice: 'Playlist updated successfully.'
    else
      redirect_to @playlist, alert: 'Failed to update playlist.'
    end
  end
  
  def add_songs
    unless @playlist.owned_by?(current_user)
      if request.xhr?
        render json: { error: 'Not authorized' }, status: :forbidden
      else
        redirect_to @playlist, alert: 'Not authorized'
      end
      return
    end
    
    song_ids = params[:song_ids]
    
    if song_ids.present?
      # Start position at 1,000,000 to add new songs at the end
      next_position = @playlist.playlists_songs.maximum(:position) || 1_000_000
      added_count = 0
      
      song_ids.each_with_index do |song_id, index|
        # Only add if not already in playlist
        unless @playlist.playlists_songs.exists?(song_id: song_id)
          @playlist.playlists_songs.create!(song_id: song_id, position: next_position + index)
          added_count += 1
        end
      end
      
      if request.xhr?
        render json: { 
          success: true, 
          message: "Added #{added_count} songs to playlist.",
          playlist_id: @playlist.id,
          playlist_name: @playlist.name
        }
      else
        redirect_to @playlist, notice: "Added #{added_count} songs to playlist."
      end
    else
      if request.xhr?
        render json: { error: 'No songs selected.' }, status: :bad_request
      else
        redirect_to @playlist, alert: 'No songs selected.'
      end
    end
  end
  
  def remove_songs
    unless @playlist.owned_by?(current_user)
      render json: { error: 'Not authorized' }, status: :forbidden
      return
    end
    
    song_ids = params[:song_ids]
    
    if song_ids.present?
      # Remove songs from playlist
      removed_count = 0
      song_ids.each do |song_id|
        playlist_song = @playlist.playlists_songs.find_by(song_id: song_id)
        if playlist_song
          playlist_song.destroy
          removed_count += 1
        end
      end
      
      if request.xhr?
        render json: { 
          success: true, 
          message: "Removed #{removed_count} songs from playlist.",
          playlist_id: @playlist.id,
          playlist_name: @playlist.name
        }
      else
        # Return the updated playlist songs for HTMX to swap
        @songs = @playlist.songs.includes(:artist, :album, :genre).order(:position, :title)
        render partial: 'playlist_songs', locals: { songs: @songs, playlist: @playlist }
      end
    else
      render json: { error: 'No song IDs provided' }, status: :bad_request
    end
  end
  
  def reorder
    Rails.logger.info "Reorder action called with params: #{params.inspect}"
    
    unless @playlist.owned_by?(current_user)
      Rails.logger.warn "User #{current_user.id} not authorized to reorder playlist #{@playlist.id}"
      render json: { error: 'Not authorized' }, status: :forbidden
      return
    end
    
    song_ids = params[:song_ids]
    Rails.logger.info "Song IDs received: #{song_ids.inspect}"
    
    if song_ids.present?
      # Update the position of each song in the playlist
      song_ids.each_with_index do |song_id, index|
        playlist_song = @playlist.playlists_songs.find_by(song_id: song_id)
        if playlist_song
          playlist_song.update(position: index + 1)
          Rails.logger.info "Updated song #{song_id} to position #{index + 1}"
        else
          Rails.logger.warn "Playlist song not found for song_id: #{song_id}"
        end
      end
      
      if request.xhr?
        render json: { 
          success: true, 
          message: "Playlist reordered successfully.",
          playlist_id: @playlist.id,
          playlist_name: @playlist.name
        }
      else
        # Return the updated playlist songs for HTMX to swap
        @songs = @playlist.songs.includes(:artist, :album, :genre).order(:position, :title)
        Rails.logger.info "Rendering partial with #{@songs.count} songs"
        render partial: 'playlist_songs', locals: { songs: @songs, playlist: @playlist }
      end
    else
      Rails.logger.warn "No song IDs provided"
      render json: { error: 'No song IDs provided' }, status: :bad_request
    end
  end
  
  private
  
  def set_playlist
    @playlist = Playlist.find_by!(id: params[:id])
  end
  
  def playlist_params
    params.require(:playlist).permit(:name, :is_public)
  end
end 