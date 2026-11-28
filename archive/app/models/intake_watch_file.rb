# A file the intake worker has taken from a watched folder (IntakeWatcher). Taken again only when its
# size or modification time changes: Lidarr replacing a file with an upgrade, for example.
class IntakeWatchFile < ApplicationRecord
  belongs_to :intake_batch, optional: true

  def same_as?(size, mtime) = byte_size == size && file_mtime.to_i == mtime.to_i
end
