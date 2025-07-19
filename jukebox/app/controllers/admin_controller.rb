class AdminController < ApplicationController
  before_action :require_admin
  
  def index
    @stats = {
      total_songs: Song.count,
      total_artists: Artist.count,
      total_albums: Album.count,
      total_genres: Genre.count,
      cached_songs: JukeboxCachedSong.count,
      queue_length: JukeboxQueueItem.count
    }
  end
end
