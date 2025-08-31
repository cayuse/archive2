class GenresController < ApplicationController
  before_action :authenticate_user!
  before_action :set_genre, only: [:show]
  
  def index
    query = params[:q]&.strip
    
    @genres = policy_scope(Genre).includes(:songs, :artists)
    
    if query.present?
      @genres = @genres.where("name ILIKE ?", "%#{query}%")
    end
    
    @genres = @genres.order(:name)
                     .page(params[:page])
                     .per(params[:per_page] || 20)
  end
  
  def show
    @songs = @genre.songs.includes(:artist, :album)
                   .order(:title)
                   .page(params[:page])
                   .per(params[:per_page] || 50)
  end
  
  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @genres = policy_scope(Genre).includes(:songs, :artists)
    
    if query.present?
      @genres = @genres.where("name ILIKE ?", "%#{query}%")
    end
    
    @genres = @genres.order(:name).page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'genres/genre_list', locals: { genres: @genres } }
      format.json { render json: { genres: @genres, has_more: @genres.count == per_page } }
    end
  end
  
  private
  
  def set_genre
    @genre = Genre.find_by!(id: params[:id])
  end
end 