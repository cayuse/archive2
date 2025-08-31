class Song < ApplicationRecord
  include ReadonlyRecord
  has_one_attached :audio_file
  # This model represents songs synced from the archive
  # It's read-only from the jukebox perspective
  
  belongs_to :artist, optional: true
  belongs_to :album, optional: true
  belongs_to :genre, optional: true
  
  has_many :jukebox_playlist_songs, class_name: 'JukeboxPlaylistSong', dependent: :destroy
  has_many :jukebox_playlists, through: :jukebox_playlist_songs, source: :jukebox_playlist
  has_many :jukebox_queue_items, class_name: 'JukeboxQueueItem', dependent: :destroy
  has_one :jukebox_cached_song, class_name: 'JukeboxCachedSong', dependent: :destroy
  
  validates :title, presence: true
  validates :file_path, presence: true
  
  # Scopes for common queries
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(processing_status: 'completed') }
  scope :by_artist, ->(artist_name) { where(artist: artist_name) }
  scope :by_album, ->(album_title) { where(album: album_title) }
  scope :by_genre, ->(genre_name) { where(genre: genre_name) }
  scope :by_year, ->(year) { where(year: year) }
  
  # Multi-term search: each term must exist somewhere (AND logic between terms)
  # "strait run" finds songs where ANY field contains "strait" AND ANY field contains "run"
  # More terms = more specific/fewer results
  def self.search(query)
    return all if query.blank?
    
    # Split query into individual terms, removing empty strings
    terms = query.strip.split(/\s+/).reject(&:blank?)
    return all if terms.empty?
    
    # Build a condition for each term that searches across all fields
    conditions = terms.map do |term|
      sanitized = ActiveRecord::Base.sanitize_sql_like(term)
      "(songs.title ILIKE ? OR artists.name ILIKE ? OR albums.title ILIKE ? OR genres.name ILIKE ?)"
    end
    
    # All terms must be found (AND logic between terms)
    where_clause = conditions.join(" AND ")
    
    # Flatten the parameters array (4 params per term: title, artist, album, genre)
    params = terms.flat_map { |term| 
      sanitized = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      [sanitized, sanitized, sanitized, sanitized] 
    }
    
    left_outer_joins(:artist, :album, :genre)
      .where(where_clause, *params)
      .distinct
      .limit(100) # Reasonable limit for performance
  end
  
  # Check if song is cached locally
  def cached?
    jukebox_cached_song.present?
  end
  
  # Get local cache path if available
  def local_path
    jukebox_cached_song&.local_path
  end
  
  # Format duration for display
  def formatted_duration
    return "Unknown" unless duration
    
    minutes = duration / 60
    seconds = duration % 60
    "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
  end
  
  # Get file size in human readable format
  def formatted_file_size
    return "Unknown" unless file_size
    
    units = ['B', 'KB', 'MB', 'GB']
    size = file_size.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(1)} #{units[unit_index]}"
  end
end 