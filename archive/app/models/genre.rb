class Genre < ApplicationRecord
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

  def default_color
    color.presence || '#6c757d'
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
    Rails.logger.error "Failed to track sync change for genre #{id}: #{e.message}"
  end
end 