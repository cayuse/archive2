class Genre < ApplicationRecord
  # Associations
  has_and_belongs_to_many :artists, join_table: :artists_genres
  has_and_belongs_to_many :albums, join_table: :albums_genres
  has_many :songs, dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true, length: { minimum: 1, maximum: 50 }
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :color, format: { 
    with: /\A#[0-9A-Fa-f]{6}\z/, 
    message: "must be a valid hex color (e.g., #FF0000)" 
  }, allow_blank: true
  
  # Scopes
  scope :by_name, -> { order(:name) }
  scope :with_artists, -> { joins(:artists).distinct }
  scope :with_albums, -> { joins(:albums).distinct }
  scope :with_songs, -> { joins(:songs).distinct }
  
  # Search scopes
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }
  scope :search_by_description, ->(query) { where("description ILIKE ?", "%#{query}%") }
  
  # Full-text search
  scope :full_text_search, ->(query) {
    return none if query.blank?
    
    search_query = query.strip
    ts_query = "plainto_tsquery('english', ?)"
    
    where("search_vector @@ #{ts_query}", search_query)
      .order("ts_rank(search_vector, #{ts_query}) DESC")
      .limit(50)
  }
  
  # Callbacks
  before_validation :normalize_name
  before_validation :normalize_color
  
  # Instance methods
  def display_name
    name
  end
  
  def color_or_default
    color.presence || "#6B7280" # Default gray color
  end
  
  def artist_count
    artists.count
  end
  
  def album_count
    albums.count
  end
  
  def song_count
    songs.count
  end
  
  def has_content?
    artists.exists? || albums.exists? || songs.exists?
  end
  
  private
  
  def normalize_name
    self.name = name.strip.titleize if name.present?
  end
  
  def normalize_color
    self.color = color.upcase if color.present?
  end
end 