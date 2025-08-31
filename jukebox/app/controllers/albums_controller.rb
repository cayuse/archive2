class AlbumsController < ApplicationController
  def index
    query = params[:q]&.strip
    
    @albums = ArchiveAlbum.includes(:songs)
    
    if query.present?
      @albums = @albums.search_by_title(query)
    end
    
    @albums = @albums.ordered
                     .page(params[:page])
                     .per(params[:per_page] || 20)
  end

  def show
    @album = ArchiveAlbum.includes(:songs).find_by!(id: params[:id])
    # Get the archive songs first
    archive_songs = @album.songs.completed.includes(:artist, :genre).order(:track_number, :title)
    # Get the corresponding Song models with audio files for the partial
    song_ids = archive_songs.pluck(:id)
    @songs = Song.where(id: song_ids).includes(:artist, :album, :genre, audio_file_attachment: :blob).order(:track_number, :title)
  end

  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @albums = ArchiveAlbum.includes(:songs)
    
    if query.present?
      @albums = @albums.search_by_title(query)
    end
    
    @albums = @albums.ordered.page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'albums/album_list', locals: { albums: @albums } }
      format.json { render json: { albums: @albums, has_more: @albums.count == per_page } }
    end
  end
end 