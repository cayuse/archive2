class Genre < ApplicationRecord
  include NaturalId
  natural_id { name }   # unique by name
  # Associations
  has_many :songs, dependent: :nullify
  has_and_belongs_to_many :artists, join_table: :artists_genres
  has_and_belongs_to_many :albums, join_table: :albums_genres
  # Get artists through songs as fallback
  has_many :song_artists, -> { distinct }, through: :songs, source: :artist

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :color, format: { with: /\A#[0-9A-F]{6}\z/i }, allow_blank: true
  validates :description, length: { maximum: 255 }, allow_blank: true

  # Scopes
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_songs, -> { joins(:songs).distinct }

  # Search scopes
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }

  # Full-text search
  scope :full_text_search, ->(query) {
    return none if query.blank?

    search_query = query.strip
    ts_query = "plainto_tsquery('english', ?)"

    where("search_vector @@ #{ts_query}", search_query)
      .order("ts_rank(search_vector, #{ts_query}) DESC")
      .limit(50)
  }


  # Instance methods
  def display_name
    name
  end

  def song_count
    songs.count
  end

  def default_color
    color.presence || "#6c757d"
  end
end
