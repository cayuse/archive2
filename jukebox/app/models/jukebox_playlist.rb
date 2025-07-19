class JukeboxPlaylist < ApplicationRecord
  self.table_name = 'jukebox_playlists'
  
  # Relationships
  has_many :playlist_songs, class_name: 'JukeboxPlaylistSong', dependent: :destroy
  has_many :songs, through: :playlist_songs, source: :archive_song
  
  # Validations
  validates :name, presence: true
  validates :archive_playlist_id, presence: true, uniqueness: true
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :jukebox_enabled, -> { where(jukebox_enabled: true) }
  
  # Settings
  attribute :crossfade_duration, :integer, default: 0
  attribute :volume, :integer, default: 80
  
  def song_count
    songs.count
  end
  
  def random_song
    songs.completed.sample
  end
  
  def random_songs(limit = 10)
    songs.completed.limit(limit).order('RANDOM()')
  end
end 