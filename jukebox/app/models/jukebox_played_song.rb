class JukeboxPlayedSong < ApplicationRecord
  self.table_name = 'jukebox_played_songs'
  validates :song_id, :played_at, :source, presence: true
  belongs_to :song, class_name: 'ArchiveSong'

  scope :recent, -> { order(played_at: :desc) }
end


