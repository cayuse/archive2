class Album < ApplicationRecord
  # Associations
  belongs_to :artist, optional: true
  has_many :songs, dependent: :nullify
  has_and_belongs_to_many :genres, join_table: :albums_genres

  # Active Storage for album cover
  has_one_attached :cover_image

  # Validations
  validates :title, presence: true, length: { maximum: 200 }
  validates :total_tracks, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true

  # Scopes
  scope :by_title, -> { order(:title) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_songs, -> { joins(:songs).distinct }

  # Search scopes
  scope :search_by_title, ->(query) { where("title ILIKE ?", "%#{query}%") }
  scope :search_by_artist, ->(query) { joins(:artist).where("artists.name ILIKE ?", "%#{query}%") }

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
  def display_title
    title
  end

  # Full date when known, otherwise just the year.
  def release_display
    release_date&.strftime("%Y-%m-%d") || release_year&.to_s
  end

  def song_count
    songs.count
  end

  def has_metadata?
    release_year.present?
  end

  def cover_image_url_or_default
    if cover_image.attached?
      cover_image
    else
      cover_image_url.presence || "default_album.jpg"
    end
  end
end
