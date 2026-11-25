# One thing a listener told a station about a song: a thumb, "sick of this track", "never play",
# or what the player observed (skipped, played to the end). Radio learns from these (StationTaste).
#
# Scope of each kind:
#   up / down   the station they were given on (jukebox). A down means "not on this station".
#               With no jukebox they are the user's own thumbs (pages outside any station).
#   tired       every station of that user, until expires_at. Never counts as dislike.
#   never       every station of that user, for good.
#   skip        the station it happened on; position = seconds into the song.
#   finished    the station it happened on.
class StationFeedback < ApplicationRecord
  VOTES = %w[up down].freeze
  EVENTS = %w[skip finished].freeze
  KINDS = (VOTES + %w[tired never] + EVENTS).freeze
  TIRED_FOR = 30.days
  EARLY_SKIP = 30.0          # seconds: a skip this early says "wrong song", later ones say little

  belongs_to :user
  belongs_to :jukebox, optional: true
  belongs_to :song

  validates :kind, inclusion: { in: KINDS }

  scope :current, -> { where("station_feedbacks.expires_at IS NULL OR station_feedbacks.expires_at > ?", Time.current) }
  scope :votes, -> { where(kind: VOTES) }

  # kind: up, down, tired, never, skip, finished, or "clear" (take back a thumb / tired / never).
  # Returns the user's standing on that song afterwards: "up", "down", "tired", "never" or nil.
  def self.record!(user:, song:, kind:, jukebox: nil, position: nil)
    kind = kind.to_s
    transaction do
      case kind
      when "clear"
        where(user_id: user.id, song_id: song.id, jukebox_id: jukebox&.id, kind: VOTES).delete_all
        where(user_id: user.id, song_id: song.id, kind: %w[tired never]).delete_all
      when *VOTES
        where(user_id: user.id, song_id: song.id, jukebox_id: jukebox&.id, kind: VOTES).delete_all
        create!(user: user, song: song, jukebox: jukebox, kind: kind)
      when "tired"
        where(user_id: user.id, song_id: song.id, kind: "tired").delete_all
        create!(user: user, song: song, jukebox: jukebox, kind: "tired", expires_at: TIRED_FOR.from_now)
      when "never"
        where(user_id: user.id, song_id: song.id, kind: %w[never tired]).delete_all
        create!(user: user, song: song, jukebox: nil, kind: "never")
      when *EVENTS
        create!(user: user, song: song, jukebox: jukebox, kind: kind, position: position&.to_f)
      else
        raise ArgumentError, "unknown feedback kind #{kind.inspect}"
      end
    end
    standing(user: user, song: song, jukebox: jukebox)
  end

  # Old thumbs API: 1, -1 or 0 (clear). Returns 1, -1 or 0.
  def self.rate!(user:, song:, value:, jukebox: nil)
    value = value.to_i
    record!(user: user, song: song, jukebox: jukebox, kind: value.zero? ? "clear" : (value.positive? ? "up" : "down"))
    value <=> 0
  end

  def self.standing(user:, song:, jukebox: nil)
    standings(user: user, song_ids: [ song.id ], jukebox: jukebox)[song.id]
  end

  # { song_id => "never" | "tired" | "up" | "down" } for the songs that have one.
  def self.standings(user:, song_ids:, jukebox: nil)
    rows = current.where(user_id: user.id, song_id: song_ids, kind: VOTES + %w[tired never])
                  .where("kind IN ('tired','never') OR jukebox_id IS NOT DISTINCT FROM ?", jukebox&.id)
                  .pluck(:song_id, :kind)
    order = %w[up down tired never]
    rows.group_by(&:first).transform_values { |list| list.map(&:last).max_by { |k| order.index(k) } }
  end

  def early_skip?
    kind == "skip" && (position.nil? || position < EARLY_SKIP)
  end
end
