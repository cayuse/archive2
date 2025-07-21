class AlbumsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_album, only: [:show]
  
  def index
    @albums = policy_scope(Album)
                  .includes(:songs, :artist)
                  .order(:title)
                  .page(params[:page])
                  .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @album.songs.includes(:artist, :genre).order(:track_number, :title)
  end
  
  def search
    query = params[:q]&.strip
    
    if query.present?
      @albums = Album.where("title ILIKE ?", "%#{query}%")
                     .order(:title)
                     .limit(10)
    else
      @albums = Album.order(:title).limit(10)
    end
    
    render partial: 'albums/search_results', locals: { albums: @albums }
  end
  
  private
  
  def set_album
    @album = Album.find_by!(id: params[:id])
  end
end 