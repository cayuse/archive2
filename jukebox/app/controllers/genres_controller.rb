class GenresController < ApplicationController
  def index
    @genres = ArchiveGenre.includes(:songs)
                         .ordered
                         .page(params[:page])
                         .per(params[:per_page] || 20)
  end

  def show
    @genre = ArchiveGenre.includes(:songs).find_by!(id: params[:id])
    @songs = @genre.songs.completed.includes(:artist, :album).order(:title)
  end

  def search
    query = params[:q]&.strip
    
    if query.present?
      @genres = ArchiveGenre.search_by_name(query)
                           .ordered
                           .limit(10)
    else
      @genres = ArchiveGenre.ordered.limit(10)
    end
    
    render partial: 'genres/search_results', locals: { genres: @genres }
  end
end 