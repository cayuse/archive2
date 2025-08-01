class Album < ApplicationRecord
  # Associations
  belongs_to :artist, optional: true
  has_many :songs, dependent: :nullify
  has_and_belongs_to_many :genres, join_table: :albums_genres

  # Active Storage for album cover
  has_one_attached :cover_image

  # Validations
  validates :name, presence: true, length: { maximum: 200 }
  validates :release_year, numericality: { only_integer: true, greater_than: 1800, less_than: 2100 }, allow_blank: true
  validates :total_tracks, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true

  # Scopes
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_songs, -> { joins(:songs).distinct }

  # Search scopes
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }
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

  # Sync tracking
  after_create :track_sync_change
  after_update :track_sync_change
  after_destroy :track_sync_change

  # Instance methods
  def display_name
    name
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

  private

  def track_sync_change
    return unless SystemSetting.sync_enabled?
    return if SystemSetting.standalone?  # Don't track in standalone mode
    
    change_type = destroyed? ? 'delete' : (previously_new_record? ? 'create' : 'update')
    
    SyncChange.create!(
      table_name: self.class.table_name,
      record_id: id,
      change_type: change_type,
      change_data: destroyed? ? nil : attributes
    )
  rescue => e
    Rails.logger.error "Failed to track sync change for album #{id}: #{e.message}"
  end
end 