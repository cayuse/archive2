class PlaylistsSong < ApplicationRecord
  self.table_name = 'playlists_songs'

  # Read-only join records from Archive
  def readonly?
    true
  end

  belongs_to :playlist, class_name: 'ArchivePlaylist'
  belongs_to :song, class_name: 'ArchiveSong'
end


