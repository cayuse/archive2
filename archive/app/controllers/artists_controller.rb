class ArtistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_artist, only: [:show]
  
  def index
    query = params[:q]&.strip
    
    @artists = policy_scope(Artist).includes(:songs, :song_genres)
    
    if query.present?
      @artists = @artists.where("name ILIKE ?", "%#{query}%")
    end
    
    @artists = @artists.order(:name)
                       .page(params[:page])
                       .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @artist.songs.includes(:album, :genre)
                   .order(:title)
                   .page(params[:page])
                   .per(params[:per_page] || 50)
  end
  
  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @artists = policy_scope(Artist).includes(:songs, :song_genres)
    
    if query.present?
      @artists = @artists.where("name ILIKE ?", "%#{query}%")
    end
    
    @artists = @artists.order(:name).page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'artists/artist_list', locals: { artists: @artists } }
      format.json { render json: { artists: @artists, has_more: @artists.count == per_page } }
    end
  end
  
  private
  
  def set_artist
    @artist = Artist.find_by!(id: params[:id])
  end
end 