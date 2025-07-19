class Album < ApplicationRecord
  # This model represents albums synced from the archive
  # It's read-only from the jukebox perspective
  
  belongs_to :artist, optional: true
  
  has_many :songs, dependent: :destroy
  
  validates :title, presence: true
  
  # Search functionality
  def self.search(query)
    where("title ILIKE ?", "%#{query}%")
  end
  
  # Get songs count for this album
  def songs_count
    songs.count
  end
  
  # Get total album duration
  def total_duration
    songs.sum(:duration)
  end
  
  # Format total duration for display
  def formatted_duration
    return "0:00" unless total_duration
    
    total_seconds = total_duration
    minutes = total_seconds / 60
    seconds = total_seconds % 60
    "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
  end
  
  # Get average song duration
  def average_song_duration
    songs.average(:duration)&.round(0)
  end
  
  # Get album size in bytes
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
  
  # Get songs ordered by track number or position
  def ordered_songs
    songs.order(:position, :title)
  end
end 