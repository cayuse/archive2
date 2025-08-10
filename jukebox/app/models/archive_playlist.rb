class ArchivePlaylist < ApplicationRecord
  self.table_name = 'playlists'

  def readonly?
    true
  end

  # Associations
  belongs_to :user, class_name: 'ArchiveUser'
  has_many :playlists_songs, class_name: 'PlaylistsSong', dependent: :destroy, foreign_key: 'playlist_id'
  has_many :songs, through: :playlists_songs, class_name: 'ArchiveSong'

  # Scopes (mirror Archive app)
  scope :publicly_visible, -> { where(is_public: true) }
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance helpers
  def display_name
    name
  end

  def public?
    is_public
  end

  def song_count
    songs.count
  end
end


