class JukeboxSelectedPlaylist < ApplicationRecord
  self.table_name = 'jukebox_selected_playlists'

  validates :playlist_id, presence: true, uniqueness: true

  belongs_to :playlist, class_name: 'ArchivePlaylist'
end


