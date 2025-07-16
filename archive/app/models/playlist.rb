class Playlist < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :playlists_songs, dependent: :destroy
  has_many :songs, through: :playlists_songs

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
    
    # Add song to end of playlist
    max_position = playlists_songs.maximum(:position) || 0
    playlists_songs.create!(song: song, position: max_position + 1)
  end
  
  def remove_song(song)
    playlists_songs.find_by(song: song)&.destroy
  end
  
  def reorder_songs(song_ids)
    # song_ids should be an array of song IDs in the desired order
    song_ids.each_with_index do |song_id, index|
      playlists_songs.find_by(song_id: song_id)&.update!(position: index + 1)
    end
    # Trigger renumbering to ensure consistency
    playlists_songs.first&.send(:renumber_playlist) if playlists_songs.any?
  end
  
  def total_duration
    songs.sum(:duration) || 0
  end
  
  def song_count
    songs.count
  end
end 