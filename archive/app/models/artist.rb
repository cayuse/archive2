class Artist < ApplicationRecord
  # Associations
  has_many :songs, dependent: :nullify
  has_many :albums, dependent: :nullify

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

  def album_count
    albums.count
  end

  def has_metadata?
    country.present? || formed_year.present?
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
    Rails.logger.error "Failed to track sync change for artist #{id}: #{e.message}"
  end
end 