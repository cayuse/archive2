class Album < ApplicationRecord
  # Associations
  belongs_to :artist
  has_many :songs, dependent: :destroy
  has_and_belongs_to_many :genres, join_table: :albums_genres

  # Active Storage for album cover
  has_one_attached :cover_image

  # Validations
  validates :title, presence: true, length: { minimum: 1, maximum: 200 }
  validates :artist, presence: true
  validates :release_date, date: { after_or_equal_to: Date.new(1900,1,1), before_or_equal_to: Date.new(2030,12,31) }, allow_blank: true
  validates :total_tracks, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
  validates :duration, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true

  # Scopes
  scope :by_title, -> { order(:title) }
  scope :by_release_date, -> { order(release_date: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def display_title
    title
  end

  def cover_image_url_or_default
    if cover_image.attached?
      cover_image
    else
      cover_image_url.presence || "default_album.jpg"
    end
  end
end 