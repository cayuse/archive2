class Artist < ApplicationRecord
  include NaturalId
  natural_id { musicbrainz_id }   # unique by MusicBrainz id, when it has one
  # Associations
  has_many :songs, dependent: :nullify
  has_many :albums, dependent: :nullify
  has_many :song_artist_credits, dependent: :destroy
  # Every song the artist is credited on, including features on other artists' songs
  has_many :credited_songs, through: :song_artist_credits, source: :song
  has_and_belongs_to_many :genres, join_table: :artists_genres
  # Get genres through songs as fallback
  has_many :song_genres, -> { distinct }, through: :songs, source: :genre

  # Validations
  validates :name, presence: true, length: { maximum: 200 }
  validates :country, length: { maximum: 100 }
  validates :formed_year, numericality: { only_integer: true, greater_than: 1800, less_than: 2100 }, allow_blank: true

  # Scopes
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_songs, -> { joins(:songs).distinct }
  scope :with_albums, -> { joins(:albums).distinct }

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


  # Instance methods
  def display_name
    name
  end

  # Songs where this is the main artist, plus songs the artist is credited on (features).
  def all_songs
    Song.where(artist_id: id).or(Song.where(id: song_artist_credits.select(:song_id)))
  end

  def song_count
    songs.count
  end

  def album_count
    albums.count
  end

  def has_metadata?
    country.present? || formed_year.present?
  end
end
