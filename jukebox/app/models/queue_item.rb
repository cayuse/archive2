class JukeboxQueueItem < ApplicationRecord
  self.table_name = 'jukebox_queue_items'
  
  # Relationships
  belongs_to :archive_song, class_name: 'ArchiveSong', foreign_key: 'song_id'
  belongs_to :user, optional: true
  
  # Validations
  validates :song_id, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[pending playing played skipped] }
  
  # Scopes
  scope :pending, -> { where(status: 'pending').order(:position) }
  scope :next_up, -> { pending.first }
  scope :recent, -> { where(status: 'played').order(played_at: :desc).limit(20) }
  
  # Callbacks
  before_create :set_position_if_not_set
  before_create :set_default_status
  
  # Status transitions
  def mark_as_playing!
    update!(status: 'playing', played_at: Time.current)
  end
  
  def mark_as_played!
    update!(status: 'played', played_at: Time.current)
  end
  
  def mark_as_skipped!
    update!(status: 'skipped', played_at: Time.current)
  end
  
  def self.add_to_queue(song_id, user = nil)
    max_position = maximum(:position) || 0
    create!(
      song_id: song_id,
      user: user,
      position: max_position + 1,
      status: 'pending'
    )
  end
  
  def self.clear_queue
    pending.update_all(status: 'skipped')
  end
  
  private
  
  def set_position_if_not_set
    return if position.present?
    
    max_position = self.class.maximum(:position) || 0
    self.position = max_position + 1
  end
  
  def set_default_status
    self.status ||= 'pending'
  end
end 