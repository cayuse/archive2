class AlbumsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_album, only: [:show]
  
  def index
    query = params[:q]&.strip
    
    @albums = policy_scope(Album).includes(:songs, :artist)
    
    if query.present?
      @albums = @albums.where("title ILIKE ?", "%#{query}%")
    end
    
    @albums = @albums.order(:title)
                     .page(params[:page])
                     .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @album.songs.includes(:artist, :genre)
                   .order(:track_number, :title)
                   .page(params[:page])
                   .per(params[:per_page] || 50)
  end
  
  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @albums = policy_scope(Album).includes(:songs, :artist)
    
    if query.present?
      @albums = @albums.where("title ILIKE ?", "%#{query}%")
    end
    
    @albums = @albums.order(:title).page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'albums/album_list', locals: { albums: @albums } }
      format.json { render json: { albums: @albums, has_more: @albums.count == per_page } }
    end
  end
  
  private
  
  def set_album
    @album = Album.find_by!(id: params[:id])
  end
end 