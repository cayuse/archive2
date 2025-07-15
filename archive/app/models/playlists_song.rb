class PlaylistsSong < ApplicationRecord
  # Associations
  belongs_to :playlist
  belongs_to :song

  # Validations
  validates :playlist, presence: true
  validates :song, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true

  # Scopes
  scope :ordered, -> { order(:position) }
end 