class PlaylistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_playlist, only: [:show]
  
  def index
    @playlists = policy_scope(Playlist)
                  .includes(:songs, :user)
                  .order(:name)
                  .page(params[:page])
                  .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @playlist.songs.includes(:artist, :album, :genre).order(:position, :title)
  end
  
  private
  
  def set_playlist
    @playlist = Playlist.find(params[:id])
  end
end 