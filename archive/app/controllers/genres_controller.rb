class GenresController < ApplicationController
  before_action :authenticate_user!
  before_action :set_genre, only: [:show]
  
  def index
    @genres = policy_scope(Genre)
                  .includes(:songs, :artists)
                  .order(:name)
                  .page(params[:page])
                  .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @genre.songs.includes(:artist, :album).order(:title)
  end
  
  def search
    query = params[:q]&.strip
    
    if query.present?
      @genres = Genre.where("name ILIKE ?", "%#{query}%")
                     .order(:name)
                     .limit(10)
    else
      @genres = Genre.order(:name).limit(10)
    end
    
    render partial: 'genres/search_results', locals: { genres: @genres }
  end
  
  private
  
  def set_genre
    @genre = Genre.find_by!(id: params[:id])
  end
end 