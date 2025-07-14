class Playlist < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :playlists_songs, dependent: :destroy
  has_many :songs, through: :playlists_songs

  # Validations
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :user, presence: true
  validates :is_public, inclusion: { in: [true, false] }

  # Scopes
  scope :publicly_visible, -> { where(is_public: true) }
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def display_name
    name
  end

  def public?
    is_public
  end
end 