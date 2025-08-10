class ArchiveSong < ApplicationRecord
  # Connect to the archive's songs table
  self.table_name = 'songs'
  
  # Active Storage attachment
  # Note: blobs were attached in Archive under record_type 'Song', so attachment access is via Song model in controllers where needed
  has_one_attached :audio_file
  
  # Read-only access
  def readonly?
    true
  end
  
  # Relationships to other archive models
  belongs_to :artist, class_name: 'ArchiveArtist', foreign_key: 'artist_id', optional: true
  belongs_to :album, class_name: 'ArchiveAlbum', foreign_key: 'album_id', optional: true
  belongs_to :genre, class_name: 'ArchiveGenre', foreign_key: 'genre_id', optional: true
  belongs_to :user, class_name: 'ArchiveUser', foreign_key: 'user_id'
  
  # Scopes for searching
  scope :search_by_title, ->(query) { where("title ILIKE ?", "%#{query}%") }
  scope :by_artist, ->(artist_id) { where(artist_id: artist_id) }
  scope :by_album, ->(album_id) { where(album_id: album_id) }
  scope :by_genre, ->(genre_id) { where(genre_id: genre_id) }
  scope :completed, -> { where(processing_status: 'completed') }
  scope :recent, -> { order(created_at: :desc) }
  
  # Helper methods
  def display_title
    title.presence || "Untitled"
  end
  
  def artist_name
    artist&.name || "Unknown Artist"
  end
  
  def album_title
    album&.title || "Unknown Album"
  end
  
  def genre_name
    genre&.name || "Unknown Genre"
  end
  
  def audio_file_url
    # This would need to be implemented based on how the archive serves files
    "/api/v1/songs/#{id}/download"
  end
end 