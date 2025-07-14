class Song < ApplicationRecord
  # Associations
  belongs_to :album
  belongs_to :genre
  has_one :artist, through: :album
  has_many :playlists_songs, dependent: :destroy
  has_many :playlists, through: :playlists_songs

  # Active Storage for audio file
  has_one_attached :audio_file

  # Validations
  validates :title, presence: true, length: { minimum: 1, maximum: 200 }
  validates :album, presence: true
  validates :genre, presence: true
  validates :track_number, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :file_format, inclusion: { in: %w[mp3 m4a mp4 ogg flac wav aac], message: "%{value} is not a supported format" }, allow_blank: true
  validates :file_size, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true

  validate :audio_file_type

  # Scopes
  scope :by_title, -> { order(:title) }
  scope :by_track, -> { order(:track_number) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_genre, ->(genre) { where(genre: genre) }
  scope :by_genre_name, ->(genre_name) { joins(:genre).where(genres: { name: genre_name }) }

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
end 