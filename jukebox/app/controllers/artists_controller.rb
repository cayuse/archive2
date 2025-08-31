class ArtistsController < ApplicationController
  def index
    query = params[:q]&.strip
    
    @artists = ArchiveArtist.includes(:songs)
    
    if query.present?
      @artists = @artists.search_by_name(query)
    end
    
    @artists = @artists.ordered
                       .page(params[:page])
                       .per(params[:per_page] || 20)
  end

  def show
    @artist = ArchiveArtist.includes(:songs).find_by!(id: params[:id])
    @songs = @artist.songs.completed.includes(:album, :genre).order(:title)
  end

  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @artists = ArchiveArtist.includes(:songs)
    
    if query.present?
      @artists = @artists.search_by_name(query)
    end
    
    @artists = @artists.ordered.page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'artists/artist_list', locals: { artists: @artists } }
      format.json { render json: { artists: @artists, has_more: @artists.count == per_page } }
    end
  end
end 