class Api::V1::PlaylistsController < ApplicationController
  before_action :authenticate_api_user!
  before_action :set_playlist, only: [:show, :add_song, :remove_song, :reorder_songs]
  
  def index
    @playlists = policy_scope(Playlist)
                  .includes(:user, :songs)
                  .order(:name)
                  .page(params[:page])
                  .per(params[:per_page] || 20)
    
    render json: {
      playlists: @playlists.map { |playlist| playlist_json(playlist) },
      pagination: {
        current_page: @playlists.current_page,
        total_pages: @playlists.total_pages,
        total_count: @playlists.total_count
      }
    }
  end
  
  def show
    authorize @playlist
    
    render json: {
      playlist: playlist_json(@playlist, include_songs: true)
    }
  end
  
  def add_song
    authorize @playlist, :manage_songs?
    
    song = Song.find(params[:song_id])
    position = params[:position] || @playlist.songs.count + 1
    
    # Add song to playlist
    @playlist.songs << song unless @playlist.songs.include?(song)
    
    # Update position if specified
    if params[:position]
      playlist_song = @playlist.playlists_songs.find_by(song: song)
      playlist_song.update(position: position) if playlist_song
    end
    
    render json: {
      success: true,
      message: "Song added to playlist",
      playlist: playlist_json(@playlist, include_songs: true)
    }
  end
  
  def remove_song
    authorize @playlist, :manage_songs?
    
    song = Song.find(params[:song_id])
    
    if @playlist.songs.include?(song)
      @playlist.songs.delete(song)
      
      # Reorder remaining songs
      @playlist.playlists_songs.order(:position).each_with_index do |playlist_song, index|
        playlist_song.update(position: index + 1)
      end
      
      render json: {
        success: true,
        message: "Song removed from playlist",
        playlist: playlist_json(@playlist, include_songs: true)
      }
    else
      render json: {
        success: false,
        error: "Song not found in playlist"
      }, status: :not_found
    end
  end
  
  def reorder_songs
    authorize @playlist, :manage_songs?
    
    song_order = params[:song_order] || []
    
    if song_order.empty?
      render json: {
        success: false,
        error: "No song order provided"
      }, status: :bad_request
      return
    end
    
    # Update positions based on provided order
    song_order.each_with_index do |song_id, index|
      playlist_song = @playlist.playlists_songs.find_by(song_id: song_id)
      playlist_song&.update(position: index + 1)
    end
    
    render json: {
      success: true,
      message: "Playlist reordered successfully",
      playlist: playlist_json(@playlist, include_songs: true)
    }
  end
  
  private
  
  def set_playlist
    @playlist = Playlist.includes(:user, :songs).find(params[:id])
  end
  
  def playlist_json(playlist, include_songs: false)
    data = {
      id: playlist.id,
      name: playlist.name,
      description: playlist.description,
      is_public: playlist.is_public,
      created_at: playlist.created_at,
      updated_at: playlist.updated_at,
      user: {
        id: playlist.user&.id,
        name: playlist.user&.name,
        email: playlist.user&.email
      },
      song_count: playlist.songs.count
    }
    
    if include_songs
      data[:songs] = playlist.songs.order('playlists_songs.position').map do |song|
        {
          id: song.id,
          title: song.title,
          track_number: song.track_number,
          duration: song.duration,
          position: playlist.playlists_songs.find_by(song: song)&.position,
          artist: {
            id: song.artist&.id,
            name: song.artist&.name
          },
          album: {
            id: song.album&.id,
            title: song.album&.title
          },
          genre: {
            id: song.genre&.id,
            name: song.genre&.name
          },
          audio_file_url: song.audio_file.attached? ? song.audio_file.url : nil,
          stream_url: song.audio_file.attached? ? api_v1_audio_file_stream_url(song) : nil
        }
      end
    end
    
    data
  end
end 