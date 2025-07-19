class JukeboxPlaylistSong < ApplicationRecord
  self.table_name = 'jukebox_playlist_songs'
  
  # Relationships
  belongs_to :jukebox_playlist, class_name: 'JukeboxPlaylist'
  belongs_to :archive_song, class_name: 'ArchiveSong', foreign_key: 'song_id'
  
  # Validations
  validates :playlist_id, presence: true
  validates :song_id, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  
  # Scopes
  scope :ordered, -> { order(:position) }
  
  # Callbacks
  before_create :set_position_if_not_set
  
  private
  
  def set_position_if_not_set
    return if position.present?
    
    max_position = jukebox_playlist.jukebox_playlist_songs.maximum(:position) || 0
    self.position = max_position + 1
  end
end 