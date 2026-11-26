# A radio station: durable, owned by one person, independent of any machine.
#
# It is a recipe (seed songs, tuning, linked playlists) plus a feedback log (StationFeedback: thumbs,
# skips, full plays) that the radio learns from. A Jukebox is what plays it on a node: the station's
# own runtime jukebox ("station-..." session id), or a party jukebox bound to it.
#
# Copies. Another person can copy a shared station. A copy is one row: it points at its parent and
# remembers when it was made. It reads the parent's log up to that moment and its own log after, so
# nothing is duplicated, the copy starts out knowing everything the original had learned, and the
# two then go their own ways. A station that has copies is archived rather than destroyed when its
# owner deletes it, so the copies keep what they were built on.
#
# Recipe digest. A hash of the things that define the station's sound before any learning (seeds,
# tuning, playlists). Equal digests = the same station definition: used to avoid making the same
# station twice, and a cheap "has this changed" for peers later.
class Station < ApplicationRecord
  MAX_PER_USER = 40
  class TooMany < StandardError; end

  belongs_to :user
  belongs_to :parent, class_name: "Station", optional: true
  has_many :copies, class_name: "Station", foreign_key: :parent_id
  has_many :station_feedbacks, dependent: :destroy
  has_many :station_playlists, dependent: :destroy
  has_many :playlists, through: :station_playlists
  has_many :jukeboxes, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }

  scope :active, -> { where(archived_at: nil) }
  scope :listed, -> { active.where(implicit: false) }            # what a person sees as "my stations"
  scope :for_user, ->(user) { listed.where(user_id: user.id).order(:created_at) }
  scope :shared_by_others, ->(user) { listed.where(shared: true).where.not(user_id: user.id).order(:name) }

  before_validation { self.origin_archive ||= SystemSetting.archive_node_id }
  before_save { self.recipe_digest = compute_recipe_digest }
  after_update_commit :rename_runtime, if: :saved_change_to_name?

  # ---- making stations

  # A person's first station, there from first use and never deleted.
  def self.first_for(user, create: true)
    for_user(user).find_by(permanent: true) ||
      (create ? create!(user: user, name: "My Station", name_edited: true, permanent: true) : nil)
  end

  # A new station, started from a song and / or a playlist. Named after what it was started from
  # unless given a name. Asking for a station whose recipe the person already has returns that one.
  def self.start!(user, name: nil, song: nil, playlist: nil, playlist_mode: "inspire")
    station = new(user: user, name: name.presence.to_s.first(255), name_edited: name.present?)
    station.settings = { "seeds" => [ song.id ] } if song
    station.station_playlists.build(playlist: playlist, mode: playlist_mode.to_s.presence_in(StationPlaylist::MODES) || "inspire") if playlist
    station.name = station.default_name(song: song, playlist: playlist) if station.name.blank?
    if (song || playlist) && name.blank?
      same = for_user(user).find_by(recipe_digest: station.compute_recipe_digest)
      return same if same
    end
    raise TooMany, "You already have #{MAX_PER_USER} stations" if for_user(user).count >= MAX_PER_USER
    station.save!
    station
  end

  # The private station behind a party jukebox's radio fill (not shown among a person's stations).
  def self.implicit_for(jukebox)
    create!(user_id: jukebox.owner_id, name: jukebox.name, name_edited: true, implicit: true,
            settings: jukebox.read_attribute(:radio_settings) || {})
  end

  def default_name(song: nil, playlist: nil)
    song ||= Song.find_by(id: seed_ids.first) if seed_ids.any?
    return "#{song.title} Radio".first(255) if song
    return "#{playlist.name} Radio".first(255) if playlist
    "New Station"
  end

  # ---- recipe

  def seed_ids
    Array(settings["seeds"])
  end

  def kept_artist_ids
    Array(settings["kept_artists"])
  end

  def learn?
    settings["learn"] != false
  end

  # Change the recipe. A station that still has the name it was given automatically is renamed
  # when its first seed changes ("the seed song as the title, until you edit it").
  def write_settings!(new_settings)
    first_seed_changed = Array(new_settings["seeds"]).first != seed_ids.first
    self.settings = new_settings
    self.name = default_name if first_seed_changed && !name_edited? && !permanent? && seed_ids.any?
    save!
  end

  def rename!(new_name)
    update!(name: new_name.to_s.strip.first(255), name_edited: true)
  end

  # Songs of the playlists this station draws on. only: just those it must stay inside (nil = none).
  def playlist_song_ids(only: false)
    links = only ? station_playlists.where(mode: "only") : station_playlists
    ids = links.pluck(:playlist_id)
    return (only ? nil : []) if ids.empty?
    PlaylistsSong.where(playlist_id: ids).distinct.pluck(:song_id)
  end

  def compute_recipe_digest
    recipe = {
      "seeds" => seed_ids.map(&:to_s).sort,
      "genre" => settings["genre"].presence || "any",
      "steer" => (settings["steer"] || {}).sort.to_h,
      "intensity" => settings["intensity"],
      "variety" => (settings["variety"] || 0.5).to_f,
      "playlists" => station_playlists.map { |l| [ l.playlist_id.to_s, l.mode ] }.sort
    }
    Digest::SHA256.hexdigest(recipe.to_json)
  end

  # ---- copies

  def copy?
    parent_id.present?
  end

  # This station and the ancestors it reads feedback from: [[station_id, cutoff or nil], ...],
  # itself first. A grandparent is read up to the earliest cutoff on the way to it.
  def lineage
    chain, cutoff, node, seen = [ [ id, nil ] ], nil, self, Set[id]
    while node.parent_id && node.forked_at
      cutoff = [ cutoff, node.forked_at ].compact.min
      node = Station.find_by(id: node.parent_id)
      break unless node && seen.add?(node.id)
      chain << [ node.id, cutoff ]
    end
    chain
  end

  # A copy for someone else (or a second one for the owner): same recipe, the log so far by
  # reference. Asking again for a station the person has already copied returns their copy.
  def copy_for!(user, name: nil)
    existing = Station.for_user(user).find_by(parent_id: id)
    return existing if existing && name.blank?
    raise TooMany, "You already have #{MAX_PER_USER} stations" if Station.for_user(user).count >= MAX_PER_USER
    transaction do
      copy = Station.create!(user: user, name: name.presence || self.name, name_edited: name.present? || name_edited?,
                             settings: settings.deep_dup.except("requests_steer"), parent: self, forked_at: Time.current)
      station_playlists.each { |l| copy.station_playlists.create!(playlist_id: l.playlist_id, mode: l.mode) }
      copy.save!   # digest now that the playlists are linked
      copy
    end
  end

  # The owner deletes the station. Its runtime jukebox goes; the station itself goes too unless
  # someone's copy is built on it, in which case it is archived (hidden, no longer changing).
  # Archived ancestors that no copy needs any more are cleared out along the way.
  def remove!
    raise ArgumentError, "This station cannot be removed" if permanent?
    transaction do
      jukeboxes.each { |j| j.station_runtime? ? j.destroy! : j.update!(station_id: nil) }
      if copies.exists?
        update!(archived_at: Time.current, shared: false)
      else
        ancestor = parent
        destroy!
        ancestor&.prune_if_unused!
      end
    end
  end

  def prune_if_unused!
    return unless archived_at? && !copies.exists?
    ancestor = parent
    destroy!
    ancestor&.prune_if_unused!
  end

  # ---- playing

  # The jukebox that plays this station on this node, made on first use.
  def runtime!
    jukeboxes.station_runtimes.first || Jukebox.create_runtime_for!(self)
  end

  private

  def rename_runtime
    jukeboxes.station_runtimes.update_all(name: name)
  end
end
