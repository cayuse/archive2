class Song < ApplicationRecord
  # Associations
  belongs_to :artist, optional: true
  belongs_to :album, optional: true
  belongs_to :genre, optional: true
  belongs_to :user, optional: true
  has_many :playlists_songs, foreign_key: :song_id, class_name: 'PlaylistsSong', dependent: :destroy, primary_key: :id
  has_many :playlists, through: :playlists_songs, source: :playlist
  has_many :ajb_queue_items, dependent: :destroy
  has_many :ajb_played_songs, dependent: :destroy

  # Active Storage for audio file
  has_one_attached :audio_file

  # Validations
  validates :title, length: { minimum: 1, maximum: 200 }, allow_blank: true
  validates :track_number, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :file_format, inclusion: { in: %w[mp3 m4a mp4 ogg flac wav aac], message: "%{value} is not a supported format" }, allow_blank: true
  validates :file_size, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :processing_status, inclusion: { in: %w[pending processing completed failed needs_review new], message: "%{value} is not a valid status" }, allow_blank: true
  validates :original_filename, length: { maximum: 255 }, allow_blank: true

  validate :audio_file_type

  # Scopes
  scope :by_title, -> { order(:title) }
  scope :by_track, -> { order(:track_number) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_genre, ->(genre) { where(genre: genre) }
  scope :by_genre_name, ->(genre_name) { joins(:genre).where(genres: { name: genre_name }) }
  
  # Processing status scopes
  scope :pending_processing, -> { where(processing_status: 'pending') }
  scope :processing, -> { where(processing_status: 'processing') }
  scope :completed, -> { where(processing_status: 'completed') }
  scope :failed, -> { where(processing_status: 'failed') }
  scope :needs_review, -> { where(processing_status: 'needs_review') }


  
  # Search scopes
  scope :search_by_title, ->(query) { where("title ILIKE ?", "%#{query}%") }
  scope :search_by_artist, ->(query) { joins(:artist).where("artists.name ILIKE ?", "%#{query}%") }
  scope :search_by_genre, ->(query) { joins(:genre).where("genres.name ILIKE ?", "%#{query}%") }
  
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
  # When inline processing is enabled, do not enqueue background jobs from the model
  unless Rails.configuration.x.inline_audio_processing
    after_commit :schedule_processing, on: :create
    after_commit :schedule_processing, on: :update, if: :should_reschedule_processing?
  end
  before_save :auto_complete_if_ready
  
  # Sync tracking
  after_create :track_sync_change
  after_update :track_sync_change
  after_destroy :track_sync_change

  # Instance methods
  def display_title
    title
  end

  def audio_file_type
    return unless audio_file.attached?
    if !audio_file.content_type.in?(%w[audio/mpeg audio/mp3 audio/x-m4a audio/mp4 audio/ogg audio/flac audio/wav audio/aac])
      errors.add(:audio_file, "must be an audio file (mp3, m4a, mp4, ogg, flac, wav, aac)")
    end
  end

  def processing_pending?
    processing_status == 'pending'
  end

  def processing_in_progress?
    processing_status == 'processing'
  end

  def processing_completed?
    processing_status == 'completed'
  end

  def processing_failed?
    processing_status == 'failed'
  end

  def needs_review?
    processing_status == 'needs_review'
  end





  def has_complete_metadata?
    title.present? && artist.present?
  end

  def has_partial_metadata?
    title.present? || artist.present? || album.present? || genre.present?
  end

  def has_no_metadata?
    !has_partial_metadata?
  end

  def extract_metadata_from_file
    return unless audio_file.attached?
    
    temp_file = download_audio_file
    processor = AudioFileProcessor.new(
      temp_file.path,
      audio_file.content_type,
      audio_file.byte_size,
      original_filename: original_filename
    )
    
    metadata = processor.process
    
    # Clean up temp file
    temp_file.close
    temp_file.unlink
    
    metadata
  rescue => e
    Rails.logger.error "Failed to extract metadata from song #{id}: #{e.message}"
    { error: e.message }
  end

  private

  def auto_complete_if_ready
    # If the song has both title and artist, and is currently 'needs_review', 
    # automatically change status to 'completed'
    if title.present? && artist.present? && needs_review?
      self.processing_status = 'completed'
      Rails.logger.info "Auto-completing song #{id} (#{title}) - has title and artist"
    end
  end

  def schedule_processing
    AudioFileProcessingJob.perform_later(id)
  end

  def should_reschedule_processing?
    audio_file.attached? && (
      processing_status.blank? ||
      processing_pending? ||
      needs_review? ||
      (processing_failed? && processing_error.blank?)
    )
  end

  def download_audio_file
    temp_file = Tempfile.new(['audio', File.extname(audio_file.filename.to_s)])
    temp_file.binmode
    
    audio_file.open do |file|
      while (chunk = file.read(16.kilobytes))
        temp_file.write(chunk)
      end
    end
    
    temp_file.rewind
    temp_file
  end

  # File sync handling
  def audio_file_available?
    return false unless audio_file.attached?
    
    # Check if file exists locally
    local_path = audio_file.path
    return true if File.exist?(local_path)
    
    # If we're a slave and file sync is in progress, file might be syncing
    if SystemSetting.slave? && SystemSetting.file_sync_in_progress?
      Rails.logger.info "Audio file for song #{id} is syncing from master"
      return false
    end
    
    # File doesn't exist and we're not syncing
    Rails.logger.warn "Audio file for song #{id} not found locally: #{local_path}"
    false
  end

  def audio_file_status
    return :not_attached unless audio_file.attached?
    return :syncing if SystemSetting.slave? && SystemSetting.file_sync_in_progress?
    return :available if audio_file_available?
    return :missing
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
    Rails.logger.error "Failed to track sync change for song #{id}: #{e.message}"
  end
end 