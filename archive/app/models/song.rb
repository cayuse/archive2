class Song < ApplicationRecord
  # Associations
  belongs_to :artist, optional: true
  belongs_to :album, optional: true
  belongs_to :genre, optional: true
  belongs_to :user, optional: true
  has_many :playlists_songs, dependent: :destroy
  has_many :playlists, through: :playlists_songs

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
  scope :new_imports, -> { where(processing_status: 'new') }
  scope :needs_attention, -> { where(processing_status: ['failed', 'needs_review', 'new']) }
  
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
  after_create :schedule_processing, if: -> { audio_file.attached? }
  after_update :schedule_processing, if: :should_reschedule_processing?

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

  def new_import?
    processing_status == 'new'
  end

  def needs_attention?
    %w[failed needs_review new].include?(processing_status)
  end

  def has_complete_metadata?
    artist.present? && album.present? && genre.present?
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
      audio_file.byte_size
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

  def schedule_processing
    AudioFileProcessingJob.perform_later(id)
  end

  def should_reschedule_processing?
    audio_file.attached? && (processing_status.blank? || (processing_failed? && processing_error.blank?))
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
end 