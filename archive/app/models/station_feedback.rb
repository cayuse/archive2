# One thing a listener told a station about a song: a thumb, "sick of this track", "never play",
# or what the player observed (skipped, played to the end). Radio learns from these (StationTaste).
#
# Scope of each kind:
#   up / down   the station they were given on. A down means "not on this station".
#   clear       takes a thumb back on that station.
#               With no station these are the user's own thumbs (pages outside any station).
#   skip        the station it happened on; position = seconds into the song.
#   finished    the station it happened on.
#   tired       every station of that user, until expires_at. Never counts as dislike.
#   never       every station of that user, for good.
#
# The station kinds are a log: rows are only ever added, and the newest thumb or "clear" for a song
# is the one that counts. That is what lets a copied station read its parent's log up to the moment
# it was copied (Station#lineage) without anything being duplicated, and it is what will let two
# archives merge their logs later. tired / never are the person's own and are not part of any
# station: a copy of somebody's station does not come with their banned songs.
class StationFeedback < ApplicationRecord
  VOTES = %w[up down].freeze
  EVENTS = %w[skip finished].freeze
  PERSONAL = %w[tired never].freeze
  KINDS = (VOTES + %w[clear] + PERSONAL + EVENTS).freeze
  TIRED_FOR = 30.days
  EARLY_SKIP = 30.0          # seconds: a skip this early says "wrong song", later ones say little

  belongs_to :user
  belongs_to :station, optional: true
  belongs_to :song

  validates :kind, inclusion: { in: KINDS }

  scope :current, -> { where("station_feedbacks.expires_at IS NULL OR station_feedbacks.expires_at > ?", Time.current) }

  # Everything that counts for +user+ listening to +station+: the station's log (its own and, for
  # a copy, what it inherited), plus the user's tired / never. With no station: the user's own thumbs.
  def self.log_for(user:, station: nil)
    if station
      scope = station.lineage.map do |station_id, cutoff|
        cutoff ? sanitize_sql([ "(station_feedbacks.station_id = ? AND station_feedbacks.created_at <= ?)", station_id, cutoff ])
               : sanitize_sql([ "station_feedbacks.station_id = ?", station_id ])
      end.join(" OR ")
    else
      scope = sanitize_sql([ "station_feedbacks.station_id IS NULL AND station_feedbacks.user_id = ?", user.id ])
    end
    current.where("(station_feedbacks.kind IN ('tired','never') AND station_feedbacks.user_id = ?) OR " \
                  "(station_feedbacks.kind NOT IN ('tired','never') AND (#{scope}))", user.id)
  end

  # { song_id => [ "up" | "down", created_at ] } from rows of [song_id, kind, created_at, ...] in
  # any order: the newest thumb or clear per song decides.
  def self.thumbs(rows)
    newest = {}
    rows.each do |song_id, kind, at|
      next unless kind == "clear" || VOTES.include?(kind)
      newest[song_id] = [ kind, at ] if newest[song_id].nil? || at > newest[song_id][1]
    end
    newest.reject { |_, (kind, _)| kind == "clear" }
  end

  # kind: up, down, tired, never, skip, finished, or "clear" (take back a thumb / tired / never).
  # Returns the user's standing on that song afterwards: "up", "down", "tired", "never" or nil.
  def self.record!(user:, song:, kind:, station: nil, position: nil)
    kind = kind.to_s
    transaction do
      case kind
      when "clear"
        create!(user: user, song: song, station: station, kind: "clear") if thumb_standing(user, song, station)
        where(user_id: user.id, song_id: song.id, kind: PERSONAL).delete_all
      when *VOTES
        create!(user: user, song: song, station: station, kind: kind)
      when "tired"
        where(user_id: user.id, song_id: song.id, kind: "tired").delete_all
        create!(user: user, song: song, kind: "tired", expires_at: TIRED_FOR.from_now)
      when "never"
        where(user_id: user.id, song_id: song.id, kind: PERSONAL).delete_all
        create!(user: user, song: song, kind: "never")
      when *EVENTS
        create!(user: user, song: song, station: station, kind: kind, position: position&.to_f)
      else
        raise ArgumentError, "unknown feedback kind #{kind.inspect}"
      end
    end
    standing(user: user, song: song, station: station)
  end

  # Old thumbs API: 1, -1 or 0 (clear). Returns 1, -1 or 0.
  def self.rate!(user:, song:, value:, station: nil)
    value = value.to_i
    record!(user: user, song: song, station: station, kind: value.zero? ? "clear" : (value.positive? ? "up" : "down"))
    value <=> 0
  end

  def self.standing(user:, song:, station: nil)
    standings(user: user, song_ids: [ song.id ], station: station)[song.id]
  end

  # { song_id => "never" | "tired" | "up" | "down" } for the songs that have one.
  def self.standings(user:, song_ids:, station: nil)
    rows = log_for(user: user, station: station).where(song_id: song_ids, kind: VOTES + %w[clear] + PERSONAL)
                                                .pluck(:song_id, :kind, :created_at)
    out = thumbs(rows).transform_values(&:first)
    rows.each { |song_id, kind, _| out[song_id] = "tired" if kind == "tired" }
    rows.each { |song_id, kind, _| out[song_id] = "never" if kind == "never" }
    out
  end

  def self.thumb_standing(user, song, station)
    rows = log_for(user: user, station: station).where(song_id: song.id, kind: VOTES + %w[clear]).pluck(:song_id, :kind, :created_at)
    thumbs(rows)[song.id]&.first
  end
  private_class_method :thumb_standing

  def early_skip?
    kind == "skip" && (position.nil? || position < EARLY_SKIP)
  end
end
