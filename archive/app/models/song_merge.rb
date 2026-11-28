# One hidden copy: +song+ was merged onto +canonical_song+, the copy that plays instead. +moves+ lists
# every row the merge changed, so SongMerger#restore! can put each back. Never deleted; a restore sets
# reverted_at.
#
# reason: superseded (a better copy arrived) / duplicate (it arrived second and was not better) /
#         manual
class SongMerge < ApplicationRecord
  REASONS = %w[superseded duplicate manual].freeze

  belongs_to :song
  belongs_to :canonical_song, class_name: "Song"

  validates :reason, inclusion: { in: REASONS }

  scope :active, -> { where(reverted_at: nil) }
end
