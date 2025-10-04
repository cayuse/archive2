class Jukebox < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :jukebox_playlist_assignments, dependent: :destroy
  has_many :playlists, through: :jukebox_playlist_assignments
  has_many :ajb_queue_items, dependent: :destroy
  has_many :ajb_played_songs, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :session_id, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :status, inclusion: { in: %w[inactive active paused ended] }
  validates :crossfade_duration, numericality: { greater_than: 0, less_than_or_equal_to: 30000 }
  validates :owner_id, presence: true
  validates :min_queue_length, presence: true, numericality: { greater_than: 0 }
  validates :queue_refill_level, presence: true, numericality: { greater_than: 0 }

  # Add associations for current song
  belongs_to :current_song, class_name: 'Song', optional: true

  scope :active, -> { where(status: 'active') }
  scope :public_jukeboxes, -> { where(private: false) }
  scope :private_jukeboxes, -> { where(private: true) }
  scope :owned_by, ->(user) { where(owner_id: user.id) }

  before_validation :generate_session_id, on: :create
  before_validation :normalize_session_id

  def active?
    status == 'active'
  end

  def ended?
    status == 'ended'
  end

  def paused?
    status == 'paused'
  end

  def inactive?
    status == 'inactive'
  end

  def public?
    !private?
  end

  def has_password?
    guest_password.present?
  end

  def start!
    update!(status: 'active', started_at: Time.current)
  end

  def pause!
    update!(status: 'paused')
  end

  def resume!
    update!(status: 'active')
  end

  def end!
    update!(status: 'ended', ended_at: Time.current)
  end

  def reset!
    update!(status: 'inactive', started_at: nil, ended_at: nil)
  end

  def scheduled_duration
    return nil unless scheduled_start && scheduled_end
    scheduled_end - scheduled_start
  end

  def actual_duration
    return nil unless started_at && ended_at
    ended_at - started_at
  end

  def current_duration
    return nil unless started_at
    ended_at || Time.current - started_at
  end

  def enabled_playlists
    jukebox_playlist_assignments.includes(:playlist).where(enabled: true)
  end

  def weighted_playlists
    enabled_playlists.order(:weight, :created_at)
  end

  private

  def generate_session_id
    return if session_id.present?
    
    base_name = name.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-').strip
    base_name = 'jukebox' if base_name.empty?
    
    # Ensure uniqueness
    counter = 1
    candidate = base_name
    while Jukebox.exists?(session_id: candidate)
      candidate = "#{base_name}-#{counter}"
      counter += 1
    end
    
    self.session_id = candidate
  end

  def normalize_session_id
    return unless session_id.present?
    self.session_id = session_id.downcase.gsub(/[^a-z0-9\-]/, '-').gsub(/-+/, '-').gsub(/^-|-$/, '')
  end
end
