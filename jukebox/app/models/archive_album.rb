class ArchiveAlbum < ApplicationRecord
  self.table_name = 'albums'
  
  def readonly?
    true
  end
  
  has_many :songs, class_name: 'ArchiveSong', foreign_key: 'album_id'
  
  scope :search_by_title, ->(query) { where("title ILIKE ?", "%#{query}%") }
  scope :ordered, -> { order(:title) }
  
  def display_title
    title.presence || "Unknown Album"
  end
end 