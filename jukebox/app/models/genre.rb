class Genre < ApplicationRecord
  include ReadonlyRecord
  # This model represents genres synced from the archive
  # It's read-only from the jukebox perspective
  
  has_many :songs, dependent: :destroy
  
  validates :name, presence: true, uniqueness: true
  
  # Search functionality
  def self.search(query)
    where("name ILIKE ?", "%#{query}%")
  end
  
  # Get songs count for this genre
  def songs_count
    songs.count
  end
  
  # Get total playtime for this genre
  def total_playtime
    songs.sum(:duration)
  end
  
  # Format total playtime for display
  def formatted_playtime
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
  
  # Get average song duration for this genre
  def average_song_duration
    songs.average(:duration)&.round(0)
  end
  
  # Get total size for this genre
  def total_size
    songs.sum(:file_size)
  end
  
  # Format total size for display
  def formatted_size
    return "Unknown" unless total_size
    
    units = ['B', 'KB', 'MB', 'GB']
    size = total_size.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(1)} #{units[unit_index]}"
  end
end 