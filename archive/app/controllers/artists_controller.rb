class ArtistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_artist, only: [:show]
  
  def index
    @artists = policy_scope(Artist)
                  .includes(:songs, :genres)
                  .order(:name)
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
    
    if query.present?
      @artists = Artist.where("name ILIKE ?", "%#{query}%")
                       .order(:name)
                       .limit(10)
    else
      @artists = Artist.order(:name).limit(10)
    end
    
    render partial: 'artists/search_results', locals: { artists: @artists }
  end
  
  private
  
  def set_artist
    @artist = Artist.find_by!(id: params[:id])
  end
end 