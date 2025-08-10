class PlaylistsController < ApplicationController
  before_action :require_admin

  def index
    # Show archive public playlists + user's own (from archive)
    @playlists = ArchivePlaylist.publicly_visible
    if current_user
      @playlists = @playlists.or(ArchivePlaylist.where(user_id: current_user.id))
    end
    @playlists = @playlists.by_name.page(params[:page]).per(params[:per_page] || 20)
  end

  def show
    @playlist = ArchivePlaylist.find(params[:id])
    @songs = @playlist.songs.includes(:artist, :album, :genre)
  end

  # Creation of archive playlists is done in Archive app; Jukebox is read-only for playlists

  # Jukebox won't modify archive playlists

  private

  def playlist_params
    params.require(:playlist).permit(:name)
  end
end


