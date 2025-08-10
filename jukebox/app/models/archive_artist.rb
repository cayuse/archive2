class ArchiveArtist < ApplicationRecord
  self.table_name = 'artists'
  
  def readonly?
    true
  end
  
  has_many :songs, class_name: 'ArchiveSong', foreign_key: 'artist_id'
  has_many :genres, -> { distinct }, through: :songs, source: :genre, class_name: 'ArchiveGenre'
  
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }
  scope :ordered, -> { order(:name) }
  
  def display_name
    name.presence || "Unknown Artist"
  end
end 