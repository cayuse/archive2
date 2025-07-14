class Artist < ApplicationRecord
  # Associations
  has_many :albums, dependent: :destroy
  has_many :songs, through: :albums
  has_and_belongs_to_many :genres, join_table: :artists_genres

  # Active Storage for artist images
  has_one_attached :image
  
  # Validations
  validates :name, presence: true, uniqueness: true, length: { minimum: 1, maximum: 100 }
  validates :country, length: { maximum: 50 }, allow_blank: true
  validates :formed_year, numericality: { 
    only_integer: true, 
    greater_than_or_equal_to: 1900, 
    less_than_or_equal_to: 2030 
  }, allow_blank: true
  validates :website, format: { 
    with: URI::regexp(%w[http https]), 
    message: "must be a valid URL" 
  }, allow_blank: true
  
  # Scopes
  scope :by_name, -> { order(:name) }
  scope :by_country, ->(country) { where(country: country) }
  scope :by_year, ->(year) { where(formed_year: year) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Search scopes
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }
  scope :search_by_country, ->(query) { where("country ILIKE ?", "%#{query}%") }
  
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
  before_validation :normalize_country
  
  # Instance methods
  def display_name
    name
  end
  
  def image_url_or_default
    if image.attached?
      image
    else
      image_url.presence || "default_artist.jpg"
    end
  end
  
  def has_albums?
    albums.exists?
  end
  
  def album_count
    albums.count
  end
  
  private
  
  def normalize_name
    self.name = name.strip.titleize if name.present?
  end
  
  def normalize_country
    self.country = country.strip.titleize if country.present?
  end
end 