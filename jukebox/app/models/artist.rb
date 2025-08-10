class Artist < ApplicationRecord
  include ReadonlyRecord
  # This model represents artists synced from the archive
  # It's read-only from the jukebox perspective
  
  has_many :songs, dependent: :destroy
  has_many :albums, dependent: :destroy
  
  validates :name, presence: true, uniqueness: true
  
  # Search functionality
  def self.search(query)
    where("name ILIKE ?", "%#{query}%")
  end
  
  # Get all songs by this artist
  def songs_count
    songs.count
  end
  
  # Get all albums by this artist
  def albums_count
    albums.count
  end
  
  # Get average song duration
  def average_song_duration
    songs.average(:duration)&.round(0)
  end
  
  # Get total playtime
  def total_playtime
    songs.sum(:duration)
  end
  
  # Format total playtime for display
  def formatted_total_playtime
    return "0:00" unless total_playtime
    
    total_seconds = total_playtime
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60
    
    if hours > 0
      "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end
end 