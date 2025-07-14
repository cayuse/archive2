class SearchController < ApplicationController
  before_action :authenticate_user!

  def index
    @query = params[:q]&.strip
    @type = params[:type] || 'all'
    @page = (params[:page] || 1).to_i
    @per_page = 20

    if @query.present?
      case @type
      when 'songs'
        @songs = Song.full_text_search(@query).includes(:artist, :genre, :album)
          .offset((@page - 1) * @per_page)
          .limit(@per_page)
        @total_songs = Song.full_text_search(@query).count
      when 'artists'
        @artists = Artist.full_text_search(@query).includes(:genres)
          .offset((@page - 1) * @per_page)
          .limit(@per_page)
        @total_artists = Artist.full_text_search(@query).count
      when 'genres'
        @genres = Genre.full_text_search(@query).includes(:artists, :albums)
          .offset((@page - 1) * @per_page)
          .limit(@per_page)
        @total_genres = Genre.full_text_search(@query).count
      else
        # Search all types
        @songs = Song.full_text_search(@query).includes(:artist, :genre, :album)
          .offset((@page - 1) * @per_page)
          .limit(@per_page)
        @artists = Artist.full_text_search(@query).includes(:genres)
          .offset((@page - 1) * @per_page)
          .limit(@per_page)
        @genres = Genre.full_text_search(@query).includes(:artists, :albums)
          .offset((@page - 1) * @per_page)
          .limit(@per_page)
        
        @total_songs = Song.full_text_search(@query).count
        @total_artists = Artist.full_text_search(@query).count
        @total_genres = Genre.full_text_search(@query).count
      end
    end

    # Handle HTMX requests
    if request.headers['HX-Request']
      render partial: 'search_results', locals: {
        songs: @songs || [],
        artists: @artists || [],
        genres: @genres || [],
        query: @query,
        type: @type,
        page: @page,
        total_songs: @total_songs || 0,
        total_artists: @total_artists || 0,
        total_genres: @total_genres || 0
      }
    end
  end

  def suggestions
    @query = params[:q]&.strip
    return render json: [] if @query.blank?

    suggestions = []
    
    # Get song suggestions
    songs = Song.search_by_title(@query).limit(5)
    suggestions += songs.map { |song| { type: 'song', text: song.title, url: song_path(song) } }
    
    # Get artist suggestions
    artists = Artist.search_by_name(@query).limit(5)
    suggestions += artists.map { |artist| { type: 'artist', text: artist.name, url: artist_path(artist) } }
    
    # Get genre suggestions
    genres = Genre.search_by_name(@query).limit(5)
    suggestions += genres.map { |genre| { type: 'genre', text: genre.name, url: genre_path(genre) } }
    
    render json: suggestions
  end
end
