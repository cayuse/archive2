class AjbQueueItem < ApplicationRecord
  belongs_to :jukebox
  belongs_to :song

  validates :jukebox_id, presence: true
  validates :song_id, presence: true
  validates :position, presence: true, numericality: { greater_than: 0 }
  validates :source, presence: true, inclusion: { in: %w[random requested] }
  
  # Ensure no duplicate songs in the same jukebox queue
  validates :song_id, uniqueness: { scope: :jukebox_id, message: "is already in this jukebox queue" }

  # Scopes
  scope :for_jukebox, ->(jukebox) { where(jukebox: jukebox) }
  scope :requested, -> { where(source: 'requested') }
  scope :random, -> { where(source: 'random') }
  scope :ordered_by_position, -> { order(:position) }
  
  # Default ordering for queue display (requested first, then random)
  scope :queue_order, -> { 
    order(
      Arel.sql("CASE WHEN source = 'requested' THEN 0 ELSE 1 END"),
      :position
    )
  }

  # Class methods
  def self.next_position_for_jukebox(jukebox)
    max_position = where(jukebox: jukebox).maximum(:position) || 0
    max_position + 1
  end

  # Instance methods
  def requested?
    source == 'requested'
  end

  def random?
    source == 'random'
  end

  # Set initial position based on queue order if not provided
  before_validation :set_default_position, on: :create

  private

  def set_default_position
    if position.nil?
      self.position = self.class.next_position_for_jukebox(jukebox)
    end
  end
end
