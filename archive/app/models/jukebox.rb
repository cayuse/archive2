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
  # Jukeboxes are always private: guests join via the per-jukebox password, and
  # the read-only API stays owner-only. The "private" toggle was removed from the
  # UI; this pins the value (and normalizes any older public rows on next save).
  before_validation { self.private = true }

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

  # Presence-driven lifecycle: the jukebox is "live" while a player is actively
  # running (the player POSTs playback_status periodically while open). When the
  # player closes, the heartbeat stops and the jukebox goes offline after
  # LIVE_WINDOW. Config, queue, and history persist regardless — the player is
  # just a window onto a durable jukebox.
  LIVE_WINDOW = 30.seconds

  def live?
    last_status_update.present? && last_status_update > LIVE_WINDOW.ago
  end

  # :live (a player is playing), :paused (player open but not playing), :offline.
  def live_status
    return :offline unless live?
    is_playing? ? :live : :paused
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
    (ended_at || Time.current) - started_at
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
