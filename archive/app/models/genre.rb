class Genre < ApplicationRecord
  # Associations
  has_many :songs, dependent: :nullify
  has_and_belongs_to_many :artists, join_table: :artists_genres
  has_and_belongs_to_many :albums, join_table: :albums_genres

  # Validations
  validates :name, presence: true, uniqueness: true, length: { minimum: 1, maximum: 100 }
  validates :color, length: { is: 7 }, allow_blank: true
  validates :description, length: { maximum: 255 }, allow_blank: true

  # Scopes
  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{query}%") }

  # Instance methods
  def display_name
    name
  end
end 