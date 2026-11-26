class Jukebox < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :jukebox_playlist_assignments, dependent: :destroy
  has_many :playlists, through: :jukebox_playlist_assignments
  has_many :ajb_queue_items, dependent: :destroy
  has_many :ajb_played_songs, dependent: :destroy
  # The Station this jukebox plays from: its seeds, tuning and what it has learned live there.
  belongs_to :station, optional: true
  after_destroy { station.destroy if station&.implicit? }

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

  # A person's stations are Station records (durable, theirs, copyable). Each has a runtime jukebox
  # on this node that plays it: a jukebox on radio auto-fill with no playlists of its own,
  # recognised by this session_id prefix. The station pages and the player daemon work with these
  # runtime jukeboxes; the methods below hand them out.
  STATION_PREFIX = "station-".freeze
  MAX_STATIONS = Station::MAX_PER_USER
  TooManyStations = Station::TooMany

  scope :stations, -> { where("session_id LIKE ?", "#{STATION_PREFIX}%") }
  scope :station_runtimes, -> { stations }

  def self.station_code(user)
    "#{STATION_PREFIX}#{user.id.to_s.delete('-').first(12)}"
  end

  # The jukebox that plays +station+ here.
  def self.create_runtime_for!(station)
    code = station_code(station.user)
    code = "#{code}-#{SecureRandom.hex(3)}" unless station.permanent? && !exists?(session_id: code)
    create!(owner: station.user, station: station, session_id: code, name: station.name, fill_mode: "radio",
            guest_password: SecureRandom.alphanumeric(8).downcase, min_queue_length: 2, queue_refill_level: 4)
  end

  # The user's first station ("My Station"), made on first use.
  def self.station_for(user)
    Station.first_for(user).runtime!
  end

  # The user's first station if it exists already (never creates one).
  def self.first_station(user)
    Station.first_for(user, create: false)&.runtime!
  end

  def self.stations_for(user)
    stations = Station.for_user(user).to_a
    stations.each(&:runtime!)
    station_runtimes.where(station_id: stations.map(&:id)).includes(:station).sort_by { |j| stations.index(j.station) }
  end

  # A new station for the user, started from a song and / or a playlist.
  def self.create_station!(user, name: nil, song: nil, playlist: nil, playlist_mode: "inspire")
    station = Station.start!(user, name: name, song: song, playlist: playlist, playlist_mode: playlist_mode)
    fresh = !station.jukeboxes.station_runtimes.exists?
    jukebox = station.runtime!
    jukebox.ajb_queue_items.create!(song: song, source: "requested") if song && fresh
    jukebox
  end

  def radio?
    fill_mode == "radio"
  end

  # Is this the runtime jukebox of a person's station (rather than a party jukebox)?
  def station?
    session_id.to_s.start_with?(STATION_PREFIX)
  end
  alias_method :station_runtime?, :station?

  # Tuning lives on the station. A jukebox with no station yet has none (reads) and gets a private
  # station of its own the first time something is stored or learned (radio_station).
  def radio_settings
    station ? station.settings : (super || {})
  end

  def radio_station
    return station if station
    update!(station: Station.implicit_for(self))
    station
  end

  def write_radio_settings!(settings)
    radio_station.write_settings!(settings)
  end

  # Songs the radio must stay inside: this jukebox's playlists and / or the station's "only"
  # playlists. nil = the whole library.
  def radio_allowed_song_ids
    playlist_ids = jukebox_playlist_assignments.enabled.pluck(:playlist_id)
    mine = playlist_ids.any? ? PlaylistsSong.where(playlist_id: playlist_ids).pluck(:song_id) : nil
    only = station&.playlist_song_ids(only: true)
    mine && only ? (mine & only) : (mine || only)
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
    write_radio_settings!(settings)
    retune!
  end

  # Start the station over from one song: it becomes the only seed, the queue is emptied and the
  # song goes to the front. What the station learned from thumbs is kept.
  def start_from!(song)
    transaction do
      write_radio_settings!(radio_settings.merge("seeds" => [ song.id ])) if radio?
      ajb_queue_items.delete_all
      ajb_queue_items.create!(song: song, source: "requested")
    end
  end

  # On a radio jukebox, drop the auto-filled songs that have not played yet, so the next top-up
  # follows the newest request or setting. Requests themselves are never dropped.
  def retune!
    return unless radio?
    ajb_queue_items.where(source: "random").delete_all
    ArchiveNode.current.push_player_command!("retune") if server_playback?   # and the one the daemon lined up
  end

  # Add associations for current song
  belongs_to :current_song, class_name: 'Song', optional: true

  # ---- Server-side playback -------------------------------------------------------------------
  # A jukebox with server_playback on is played by the node's player daemon through the node's
  # speakers instead of by a browser. A node has one set of speakers, so at most one jukebox is
  # "on air": switching another one on takes the speakers. The daemon follows server_transport;
  # the remote-control page (and admin-code guests) change it with transport!.
  SERVER_TRANSPORTS = %w[play pause stop].freeze
  TRANSPORT_COMMANDS = %w[play pause stop skip].freeze
  validates :server_transport, inclusion: { in: SERVER_TRANSPORTS }
  after_commit :announce_server_playback, if: :saved_change_to_server_playback?

  def self.on_air
    where(server_playback: true).order(updated_at: :desc).first
  end

  # Take the speakers. Whatever a browser was playing carries over: the daemon picks the current
  # song up where it was (see server_resume). fresh: start from the queue instead.
  def start_server_playback!(transport: nil, fresh: false)
    transaction do
      Jukebox.where(server_playback: true).where.not(id: id).find_each(&:end_server_playback!)
      carry = live? && is_playing?
      attrs = { server_playback: true }
      attrs.merge!(current_song_id: nil, current_position: 0, is_playing: false) if fresh
      unless server_playback? && transport.nil?
        attrs[:server_transport] = transport || (carry ? "play" : (current_song_id && !fresh ? "pause" : "stop"))
      end
      attrs[:current_position] = estimated_position if !fresh && attrs[:server_transport] == "pause"
      update!(attrs)
    end
  end

  # Give the speakers back. The song and position are kept, so a browser player that is open (or
  # opened later) comes up paused at the same spot; nothing is left playing.
  def end_server_playback!
    update!(server_playback: false, server_transport: "stop", current_position: estimated_position, is_playing: false)
  end

  # play / pause / stop / skip for a server-played jukebox.
  # quiet: a skip that is not held against the song (it follows a thumbs down, which already was).
  def transport!(command, quiet: false)
    command = command.to_s
    raise ArgumentError, "unknown command #{command}" unless TRANSPORT_COMMANDS.include?(command)
    raise ArgumentError, "this jukebox is not playing on the archive's speakers" unless server_playback?
    case command
    when "play"  then update!(server_transport: "play")
    when "pause" then update!(server_transport: "pause", current_position: estimated_position, is_playing: false)
    when "stop"  then update!(server_transport: "stop", current_song_id: nil, current_position: 0, is_playing: false)
    when "skip"  then ArchiveNode.current.push_player_command!("skip", { "report" => !quiet })
    end
  end

  # Where the current song is right now: the last reported position, moved on by the time since
  # then while a player is live and playing.
  def estimated_position
    position = current_position.to_f
    position += Time.current - last_status_update if is_playing? && live?
    position
  end

  # The song a daemon taking over should start with, and where in it; nil to start from the queue.
  def server_resume
    return nil if server_transport == "stop" || current_song.nil?
    position = estimated_position
    length = current_song.duration.to_f
    return nil if length.positive? && position >= length - 5
    [ current_song, position ]
  end

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
    code = code.to_s
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

  # What API clients (station pages, the player daemon) know a jukebox by.
  def station_json
    {
      id: id, name: name, session_id: session_id, fill_mode: fill_mode,
      station: station?, guest_password: guest_password,
      radio: {
        genre: radio_genre_mode, steer: radio_steer,
        intensity: radio_intensity, variety: radio_variety,
        learn: radio_learn?, requests_steer: requests_steer?,
        seeds: radio_seed_ids
      },
      queue_length: ajb_queue_items.count,
      live: live?,
      server_playback: server_playback?, transport: server_transport,
      station_id: station_id, shared: station&.shared? || false, name_edited: station&.name_edited? || false,
      permanent: station&.permanent? || false,
      copied_from: station&.parent && { name: station.parent.name, owner: station.parent.user&.name },
      playlists: station ? station.station_playlists.includes(:playlist).map { |l| { id: l.playlist_id, name: l.playlist&.name, mode: l.mode } } : []
    }
  end

  private

  # Open player / remote pages swap over when the speakers are taken or given back.
  def announce_server_playback
    ActionCable.server.broadcast("jukebox_#{id}", { type: "server_playback", on: server_playback? })
  rescue => e
    Rails.logger.warn "server_playback broadcast failed: #{e.message}"
  end

  def update_setting!(key, value)
    write_radio_settings!(radio_settings.merge(key => value))
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
