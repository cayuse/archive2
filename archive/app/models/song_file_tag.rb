# The tags embedded in a song's audio file, exactly as the scanner read them.
# Filled by `rails library:import_file_tags[path]`; never edited by hand.
class SongFileTag < ApplicationRecord
  belongs_to :song

  validates :song_id, uniqueness: true

  scope :scanned_ok, -> { where(scan_error: nil) }
  scope :with_recording_id, -> { where.not(musicbrainz_recording_id: nil) }
  scope :without_recording_id, -> { where(musicbrainz_recording_id: nil) }
end
