class ArtistsController < ApplicationController
  def index
    @artists = ArchiveArtist.includes(:songs)
                           .ordered
                           .page(params[:page])
                           .per(params[:per_page] || 20)
  end

  def show
    @artist = ArchiveArtist.includes(:songs).find_by!(id: params[:id])
    @songs = @artist.songs.completed.includes(:album, :genre).order(:title)
  end

  def search
    query = params[:q]&.strip
    
    if query.present?
      @artists = ArchiveArtist.search_by_name(query)
                             .ordered
                             .limit(10)
    else
      @artists = ArchiveArtist.ordered.limit(10)
    end
    
    render partial: 'artists/search_results', locals: { artists: @artists }
  end
end 