class Jukebox < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :jukebox_playlist_assignments, dependent: :destroy
  has_many :playlists, through: :jukebox_playlist_assignments
  has_many :ajb_queue_items, dependent: :destroy
  has_many :ajb_played_songs, dependent: :destroy
  has_many :station_feedbacks, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  # Guests always join with a password — a jukebox can't exist without one.
  validates :guest_password, presence: true
  # Optional second code: guests who join with it get the admin controls. It
  # must differ from the guest code, or the code alone couldn't tell them apart.
  validates :admin_password, comparison: { other_than: :guest_password, message: "must be different from the guest code" },
                             allow_blank: true
  validates :session_id, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :status, inclusion: { in: %w[inactive active paused ended] }
  validates :crossfade_duration, numericality: { greater_than: 0, less_than_or_equal_to: 30000 }
  validates :owner_id, presence: true
  validates :min_queue_length, presence: true, numericality: { greater_than: 0 }
  validates :queue_refill_level, presence: true, numericality: { greater_than: 0 }
  FILL_MODES = %w[random radio].freeze
  validates :fill_mode, inclusion: { in: FILL_MODES }

  # A user's stations: jukeboxes on radio auto-fill with no playlists, so they draw on the whole
  # library. Recognised by this session_id prefix. Everyone who may host has a first one ("My
  # Station", created on first use) and can add more, each with its own seeds, tuning and feedback.
  STATION_PREFIX = "station-".freeze
  MAX_STATIONS = 40
  class TooManyStations < StandardError; end

  scope :stations, -> { where("session_id LIKE ?", "#{STATION_PREFIX}%") }

  def self.station_code(user)
    "#{STATION_PREFIX}#{user.id.to_s.delete('-').first(12)}"
  end

  def self.station_for(user)
    code = station_code(user)
    find_by(owner_id: user.id, session_id: code) || create_station!(user, name: "My Station", session_id: code)
  end

  # The user's first station if it exists already (never creates one).
  def self.first_station(user)
    find_by(owner_id: user.id, session_id: station_code(user))
  end

  def self.stations_for(user)
    stations.where(owner_id: user.id).order(:created_at)
  end

  # A new station for the user, optionally started from a song (named after it unless given a name).
  def self.create_station!(user, name: nil, song: nil, session_id: nil)
    raise TooManyStations, "You already have #{MAX_STATIONS} stations" if session_id.nil? && stations_for(user).count >= MAX_STATIONS
    station = create!(
      owner: user, session_id: session_id || "#{station_code(user)}-#{SecureRandom.hex(3)}",
      name: (name.presence || (song ? "#{song.title} Radio" : "New Station")).to_s.first(255), fill_mode: "radio",
      guest_password: SecureRandom.alphanumeric(8).downcase,
      min_queue_length: 2, queue_refill_level: 4
    )
    station.start_from!(song) if song
    station
  end

  def radio?
    fill_mode == "radio"
  end

  def station?
    session_id.to_s.start_with?(STATION_PREFIX)
  end

  def radio_genre_mode
    radio_settings["genre"].presence || "any"
  end

  # Leanings on the mood dials. Energy is not one of them: see radio_intensity.
  def radio_steer
    (radio_settings["steer"] || {}).slice(*SongRadio::STEER_DIALS)
  end

  # -1.0 (mellow) .. 1.0 (high), or nil to stay at the level of the seed songs.
  def radio_intensity
    radio_settings["intensity"]&.to_f
  end

  # 0.0 (steady) .. 1.0 (dynamic): how far energy rises and falls over a run of songs.
  def radio_variety
    (radio_settings["variety"] || 0.5).to_f
  end

  # Learn a taste and dial leanings from thumbs and skips (on unless switched off).
  def radio_learn?
    radio_settings["learn"] != false
  end

  # Does a request re-aim the station (drop what was lined up and follow the request)? Yes on a
  # personal station; on a party jukebox a guest's request should not change what everyone hears next.
  def requests_steer?
    radio_settings.key?("requests_steer") ? radio_settings["requests_steer"] == true : station?
  end

  # The songs the station is built around. Empty on a party jukebox: it follows the latest request.
  def radio_seed_ids
    Array(radio_settings["seeds"])
  end

  # Artists the listener put back after two thumbs down took them off the station.
  def radio_kept_artist_ids
    Array(radio_settings["kept_artists"])
  end

  def add_seed!(song)
    update_setting!("seeds", (radio_seed_ids + [ song.id ]).uniq.last(SongRadio::MAX_SEEDS))
  end

  def remove_seed!(song_id)
    update_setting!("seeds", radio_seed_ids - [ song_id.to_s ])
  end

  def keep_artist!(artist_id)
    update_setting!("kept_artists", (radio_kept_artist_ids + [ artist_id.to_s ]).uniq)
  end

  # Store tuning from params-like input:
  #   { genre: "adjacent", intensity: 0.5 | "auto", variety: 0.3, learn: true, requests_steer: false,
  #     acousticness: 0.6, ... }
  # Dials not mentioned keep their value; a dial set to 0 is removed. "energy" is accepted from older
  # clients and stored as intensity.
  def update_radio_settings!(attrs)
    attrs = attrs.to_h.stringify_keys
    settings = radio_settings.deep_dup
    settings["genre"] = attrs["genre"] if SongRadio::GENRE_MODES.include?(attrs["genre"])
    steer = (settings["steer"] || {}).slice(*SongRadio::STEER_DIALS)
    if attrs["reset_steer"].to_s == "true"
      steer = {}
      settings.delete("intensity")
    end
    SongRadio::STEER_DIALS.each do |dial|
      next unless attrs.key?(dial)
      value = attrs[dial].to_f.clamp(-1.0, 1.0)
      value.zero? ? steer.delete(dial) : steer[dial] = value
    end
    settings["steer"] = steer
    intensity = attrs.key?("intensity") ? attrs["intensity"] : attrs["energy"]
    unless intensity.nil?
      auto = intensity.to_s.in?([ "", "auto" ]) || (!attrs.key?("intensity") && intensity.to_f.zero?)
      auto ? settings.delete("intensity") : settings["intensity"] = intensity.to_f.clamp(-1.0, 1.0)
    end
    settings["variety"] = attrs["variety"].to_f.clamp(0.0, 1.0) if attrs.key?("variety")
    %w[learn requests_steer].each do |flag|
      settings[flag] = ActiveModel::Type::Boolean.new.cast(attrs[flag]) == true if attrs.key?(flag)
    end
    update!(radio_settings: settings)
    retune!
  end

  # Start the station over from one song: it becomes the only seed, the queue is emptied and the
  # song goes to the front. What the station learned from thumbs is kept.
  def start_from!(song)
    transaction do
      update!(radio_settings: radio_settings.merge("seeds" => [ song.id ])) if radio?
      ajb_queue_items.delete_all
      ajb_queue_items.create!(song: song, source: "requested")
    end
  end

  # On a radio jukebox, drop the auto-filled songs that have not played yet, so the next top-up
  # follows the newest request or setting. Requests themselves are never dropped.
  def retune!
    ajb_queue_items.where(source: "random").delete_all if radio?
  end

  # Add associations for current song
  belongs_to :current_song, class_name: 'Song', optional: true

  scope :active, -> { where(status: 'active') }
  scope :public_jukeboxes, -> { where(private: false) }
  scope :private_jukeboxes, -> { where(private: true) }
  scope :owned_by, ->(user) { where(owner_id: user.id) }

  before_validation :generate_session_id
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

  # Which role a join code grants on the guest page: :admin, :guest or nil.
  def guest_role_for(code)
    return nil if code.blank?
    return :admin if admin_password.present? && ActiveSupport::SecurityUtils.secure_compare(admin_password, code)
    return :guest if ActiveSupport::SecurityUtils.secure_compare(guest_password.to_s, code)
    nil
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

  def update_setting!(key, value)
    update!(radio_settings: radio_settings.merge(key => value))
    retune!
  end

  def generate_session_id
    return if session_id.present?
    
    base_name = name.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-').strip
    base_name = 'jukebox' if base_name.empty?
    
    # Ensure uniqueness (excluding ourselves, so re-saving doesn't collide).
    counter = 1
    candidate = base_name
    while Jukebox.where(session_id: candidate).where.not(id: id).exists?
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
