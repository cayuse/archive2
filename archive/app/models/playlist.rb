class Playlist < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :playlists_songs, foreign_key: :playlist_id, class_name: 'PlaylistsSong', dependent: :destroy, primary_key: :id
  has_many :songs, through: :playlists_songs, source: :song

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :user, presence: true
  validates :is_public, inclusion: { in: [true, false] }

  # Scopes
  scope :publicly_visible, -> { where(is_public: true) }
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def display_name
    name
  end

  def public?
    is_public
  end
  
  def owned_by?(user)
    self.user == user
  end
  
  def add_song(song)
    return false if songs.include?(song)
    
    # Add song to end of playlist using explicit SQL to avoid UUID association issues
    max_position = PlaylistsSong.where(playlist_id: id).maximum(:position) || 0
    PlaylistsSong.create!(playlist_id: id, song_id: song.id, position: max_position + 1)
  end
  
  def remove_song(song)
    # Use explicit SQL to avoid UUID association issues
    PlaylistsSong.where(playlist_id: id, song_id: song.id).first&.destroy
  end
  
  def reorder_songs(song_ids)
    # song_ids should be an array of song IDs in the desired order
    song_ids.each_with_index do |song_id, index|
      # Use explicit SQL to avoid UUID association issues
      PlaylistsSong.where(playlist_id: id, song_id: song_id).first&.update!(position: index + 1)
    end
    # Trigger renumbering to ensure consistency
    # Use explicit SQL to avoid UUID association issues
    first_item = PlaylistsSong.where(playlist_id: id).first
    first_item&.send(:renumber_playlist) if first_item
  end
  
  def total_duration
    songs.sum(:duration) || 0
  end
  
  def song_count
    songs.count
  end
end 