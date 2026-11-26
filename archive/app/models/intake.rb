# Where the drop box keeps files on disk, and the rules for what it accepts.
#
#   incoming/<batch>/   as uploaded, folder structure kept
#   work/<batch>/       a batch being dealt with (archives unpacked here)
#   originals/<batch>/  untouched copies of files whose tags were rewritten, and the archives
#                       they came in; removed after KEEP_ORIGINALS
module Intake
  AUDIO = %w[mp3 flac m4a mp4 ogg oga opus wav aac].freeze
  ARCHIVES = /\.(zip|tar|tgz|tbz2|txz|7z|rar|tar\.(gz|bz2|xz|zst))\z/i
  KEEP_ORIGINALS = 30.days
  MAX_ARCHIVE_ENTRIES = 20_000
  MAX_ARCHIVE_BYTES = 50.gigabytes
  MAX_NESTING = 3
  WORKER_LOCK = 742_611_260   # advisory lock number held by the one running intake worker

  def self.root = Pathname.new(ENV["INTAKE_ROOT"].presence || Rails.root.join("tmp", "intake", Rails.env).to_s)

  # A client-supplied path made safe to join under a directory: no "..", no absolute paths, no
  # control characters, no empty or dot-only segments.
  def self.safe_path(path)
    parts = path.to_s.scrub("").tr("\\", "/").split("/").map { |p| p.gsub(/[[:cntrl:]]/, "").strip }
                .reject { |p| p.empty? || p.match?(/\A\.+\z/) }.map { |p| p.byteslice(0, 200).scrub("") }
    raise ArgumentError, "no file name" if parts.empty?
    parts.join("/")
  end

  def self.audio?(path) = AUDIO.include?(File.extname(path.to_s).delete(".").downcase)
  def self.archive?(path) = path.to_s.match?(ARCHIVES)

  # Removes originals kept longer than KEEP_ORIGINALS. Returns how many batches were cleared.
  def self.prune_originals(now: Time.current)
    dirs = Dir.glob(root.join("originals", "*").to_s).select { |d| File.directory?(d) && File.mtime(d) < now - KEEP_ORIGINALS }
    dirs.each { |d| FileUtils.rm_rf(d) }
    dirs.size
  end
end
