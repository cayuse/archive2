class SongsController < ApplicationController
  def index
    @songs = Song.completed
                  .includes(:artist, :album, :genre)
                  .recent
                  .page(params[:page])
                  .per(params[:per_page] || 20)
  end

  def show
    @song = Song.includes(:artist, :album, :genre).find_by!(id: params[:id])
  end

  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @songs = Song.completed
                  .includes(:artist, :album, :genre)
                  .recent
    
    if query.present?
      @songs = @songs.search(query)
    end
    
    @songs = @songs.page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'songs/song_list', locals: { songs: @songs } }
      format.json { render json: { songs: @songs, has_more: @songs.count == per_page } }
    end
  end
end 