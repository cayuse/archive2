# Why a song is what it is. A song can carry several at once: a broken file that was later replaced
# is "broken" (resolved, with what replaced it) and "superseded" (open while it stays hidden).
#
# kind:    broken        its file is damaged in a way you hear, or unreadable: find a replacement
#          flawed        plays, with a fault: replace it when a better copy turns up
#          low_fidelity  intact, but low bitrate or made from a lower-quality copy
#          superseded    hidden: a better copy of the same recording arrived (related_song)
#          duplicate     hidden: arrived when the library already had an as-good copy (related_song)
# source:  audit / intake / manual
class SongIssue < ApplicationRecord
  KINDS = %w[broken flawed low_fidelity superseded duplicate].freeze
  QUALITY_KINDS = { "bad" => "broken", "flawed" => "flawed", "weak" => "low_fidelity" }.freeze
  SOURCES = %w[audit intake manual].freeze

  belongs_to :song
  belongs_to :related_song, class_name: "Song", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }

  scope :open, -> { where(resolved_at: nil) }
  scope :quality, -> { where(kind: QUALITY_KINDS.values) }

  # Songs to find a better copy of, worst first: open quality issues on songs that still play.
  scope :wanted, -> { open.quality.joins(:song).merge(Song.live) }

  # Records the quality issue a measurement implies (none for "ok"), replacing an older open one.
  def self.record_quality!(song, measurement, source:)
    kind = QUALITY_KINDS[measurement.verdict]
    open.quality.where(song: song).where.not(kind: kind).update_all(resolved_at: Time.current, updated_at: Time.current)
    return unless kind
    issue = open.find_or_initialize_by(song: song, kind: kind)
    issue.update!(source: issue.source || source, detail: { "problems" => measurement.problems, "quality" => measurement.quality })
  end

  def resolve!(detail = {})
    update!(resolved_at: Time.current, detail: self.detail.merge(detail))
  end
end
