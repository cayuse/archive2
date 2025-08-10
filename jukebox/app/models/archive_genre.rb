class ArchiveGenre < ApplicationRecord
  self.table_name = 'genres'
  
  def readonly?
    true
  end
  
  has_many :songs, class_name: 'ArchiveSong', foreign_key: 'genre_id'
  has_many :artists, -> { distinct }, through: :songs, source: :artist, class_name: 'ArchiveArtist'
  
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }
  scope :ordered, -> { order(:name) }
  
  def display_name
    name.presence || "Unknown Genre"
  end
end 