class GenresController < ApplicationController
  def index
    query = params[:q]&.strip
    
    @genres = ArchiveGenre.includes(:songs)
    
    if query.present?
      @genres = @genres.search_by_name(query)
    end
    
    @genres = @genres.ordered
                     .page(params[:page])
                     .per(params[:per_page] || 20)
  end

  def show
    @genre = ArchiveGenre.includes(:songs).find_by!(id: params[:id])
    # Get the archive songs first
    archive_songs = @genre.songs.completed.includes(:artist, :album)
                           .order(:title)
                           .page(params[:page])
                           .per(params[:per_page] || 50)
    # Get the corresponding Song models with audio files for the partial
    song_ids = archive_songs.pluck(:id)
    @songs = Song.where(id: song_ids).includes(:artist, :album, :genre, audio_file_attachment: :blob).order(:title)
  end

  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @genres = ArchiveGenre.includes(:songs)
    
    if query.present?
      @genres = @genres.search_by_name(query)
    end
    
    @genres = @genres.ordered.page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'genres/genre_list', locals: { genres: @genres } }
      format.json { render json: { genres: @genres, has_more: @genres.count == per_page } }
    end
  end
end 