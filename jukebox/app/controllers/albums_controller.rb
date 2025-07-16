class AlbumsController < ApplicationController
  def index
    @albums = ArchiveAlbum.includes(:songs)
                         .ordered
                         .page(params[:page])
                         .per(params[:per_page] || 20)
  end

  def show
    @album = ArchiveAlbum.includes(:songs).find_by!(id: params[:id])
    @songs = @album.songs.completed.includes(:artist, :genre).order(:track_number, :title)
  end

  def search
    query = params[:q]&.strip
    
    if query.present?
      @albums = ArchiveAlbum.search_by_title(query)
                           .ordered
                           .limit(10)
    else
      @albums = ArchiveAlbum.ordered.limit(10)
    end
    
    render partial: 'albums/search_results', locals: { albums: @albums }
  end
end 