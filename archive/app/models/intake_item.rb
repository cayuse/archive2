# What became of one file in a drop.
#
# status:
#   received   seen, not dealt with yet
#   imported   now a song (song_id); +identified+ says how it was recognised
#   duplicate  already in the library (song_id is the song it duplicates); nothing was added
#   rejected   not something the library takes (not audio, unreadable archive, ...)
#   expanded   an archive; its contents are listed as items of their own
#   failed     something went wrong; +message+ says what
# identified: "album" / "track" / "recording" / "ids" (found in MusicBrainz that way) or "tags" (not found;
# filed under what the file's own tags say)
class IntakeItem < ApplicationRecord
  STATUSES = %w[received imported duplicate rejected expanded failed].freeze

  belongs_to :intake_batch
  belongs_to :song, optional: true

  validates :status, inclusion: { in: STATUSES }

  def as_status_json
    { path: relative_path, status: status, identified: identified, message: message, size: byte_size,
      song: song && { id: song.id, title: song.title, artist: song.artist_display, album: song.album&.title,
                      track: song.track_number, needs_review: song.processing_status == "needs_review" } }
  end
end
