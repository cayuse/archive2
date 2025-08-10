class JukeboxQueueItem < ApplicationRecord
  self.table_name = 'jukebox_queue_items'
  
  # Relationships
  belongs_to :song, class_name: 'ArchiveSong', foreign_key: 'song_id', optional: true
  belongs_to :user, optional: true
  
  # Validations
  validates :song_id, presence: true
  validates :position, numericality: { only_integer: true }, allow_nil: true
  # status is treated as numeric string priority: '0' (manual) or '1' (random)
  
  # Scopes
  scope :manual, -> { where(status: ['0', 'pending']) }
  scope :random_src, -> { where(status: ['1', 'pending_random']) }
  # Combined ordering for playback: manual first, then random, each by position
  scope :ordered_for_playback, lambda {
    where(status: ['0','1','pending','pending_random'])
      .order(Arel.sql("CASE WHEN status IN ('0','pending') THEN 0 WHEN status IN ('1','pending_random') THEN 1 ELSE 2 END, position ASC"))
  }
  scope :next_up, -> { ordered_for_playback.first }
  scope :recent, -> { where(status: 'played').order(played_at: :desc).limit(20) }
  
  # Callbacks
  before_create :set_position_placeholder
  after_create :set_position_to_id_if_blank
  
  # Status transitions
  # status transition helpers removed; consumption deletes the row
  
  def self.add_to_queue(song_id, user = nil)
    create!(song_id: song_id, user: user, status: '0')
  end

  def self.add_random_to_queue(song_id)
    create!(song_id: song_id, status: '1')
  end
  
  def self.clear_queue
    pending.update_all(status: 'skipped')
  end
  
  private
  
  def set_position_placeholder
    # Satisfy NOT NULL constraint; will be corrected to id after create
    self.position ||= 0
  end

  def set_position_to_id_if_blank
    if self.position.nil?
      update_column(:position, self.id)
    elsif self.position == 0
      update_column(:position, self.id)
    end
  end
end 