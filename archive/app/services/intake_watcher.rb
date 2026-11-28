require "find"

# Watched folders: music that appears in them goes into the library with no one dropping it on the
# page. Configured with INTAKE_WATCH, "name=path" pairs separated by ";":
#
#   INTAKE_WATCH="lidarr=/watch/lidarr;drop=/watch/drop"
#
# lidarr  Lidarr's root folder: Artist/Album (Year)/tracks, identified by Lidarr against MusicBrainz.
# drop    a folder for anything else (purchases, downloads), in any layout: loose files, Artist/Album,
#         Album [FLAC]/CD1, archives. Folders are only a hint; the Drop Box identifies files by their
#         tags and sound.
#
# Every audio file and archive is taken once (IntakeWatchFile), and again only when its size or time
# changes (Lidarr replacing it with an upgrade). Files are copied, never moved: the watched folder is
# never written to. A unit (an album folder, or the loose files at the top) is taken only when nothing
# in it has changed for SETTLE, so a copy still arriving over the network is never read half-written.
# Hidden files, Mac resource forks, and partial downloads are skipped; other non-audio is not taken.
class IntakeWatcher
  SETTLE = 5.minutes
  SKIP = /\A(\.|~\$)|\A(Thumbs\.db|desktop\.ini)\z|\.(part|partial|tmp|temp|crdownload|!qb|download|aria2)\z/i
  # how many folder levels make one unit: Lidarr is always Artist/Album; elsewhere the top folder
  DEPTH = { "lidarr" => 2 }.freeze
  # units queued per look: a backlog (Lidarr delivered 321 GB before the first look) is taken a few
  # albums at a time, so copying and importing take turns instead of copying everything first
  UNITS_PER_SCAN = 5

  def self.watches
    ENV.fetch("INTAKE_WATCH", "").split(";").filter_map do |pair|
      name, path = pair.split("=", 2).map { |x| x.to_s.strip }
      [ name, Pathname.new(path) ] if name.present? && path.present?
    end
  end

  # The account watched batches are filed under: INTAKE_WATCH_USER (an email), or the first admin.
  def self.user = User.find_by(email: ENV["INTAKE_WATCH_USER"].presence) || User.admins.order(:created_at).first

  # Watching waits until the library's own measurements are loaded (rake library:load_audit): until
  # then every arriving copy would look new, and nothing would be merged.
  # (asks the database each time: Model.table_exists? is cached for the life of the process, and the
  # worker starts before its release's migration has run)
  def self.ready?
    conn = ActiveRecord::Base.connection
    conn.table_exists?("intake_watch_files") && conn.table_exists?("song_measurements") && SongMeasurement.exists?
  end

  # Looks at the watched folders once and queues up to +limit+ units. Returns the batches it queued.
  def self.scan_all(now: Time.current, log: Rails.logger, limit: UNITS_PER_SCAN)
    user = self.user
    return [] unless user && ready?
    watches.each_with_object([]) do |(name, root), queued|
      break queued if queued.size >= limit
      queued.concat(new(name, root, user: user, now: now, log: log).scan(limit: limit - queued.size))
    end
  end

  # A batch a stopped worker left half-copied: its files were never marked as taken, so they are
  # taken again on the next look. Removes such batches and their copies.
  def self.clear_unfinished
    IntakeBatch.where(status: "uploading").where("source like 'watch:%'").find_each do |batch|
      IntakeWatchFile.where(intake_batch_id: batch.id).delete_all
      batch.discard!
    end
  end

  def initialize(name, root, user:, now: Time.current, log: Rails.logger)
    @name = name
    @root = Pathname.new(root)
    @user = user
    @now = now
    @log = log
  end

  def scan(limit: nil)
    return [] unless @root.directory?
    units = Hash.new { |h, k| h[k] = [] }
    each_file { |rel, stat| units[unit_of(rel)] << [ rel, stat.size, stat.mtime ] }
    queued = []
    units.sort.each do |unit, files|
      break if limit && queued.size >= limit
      next if files.map(&:last).max > @now - SETTLE   # still arriving
      known = IntakeWatchFile.where(watch: @name, path: files.map(&:first)).index_by(&:path)
      fresh = files.reject { |rel, size, mtime| known[rel]&.same_as?(size, mtime) }
      batch = queue(unit, fresh) if fresh.any?
      queued << batch if batch
    end
    queued
  end

  private

  def each_file
    Find.find(@root.to_s) do |path|
      base = File.basename(path)
      if File.directory?(path)
        Find.prune if path != @root.to_s && base.start_with?(".")
        next
      end
      next if base.match?(SKIP) || File.symlink?(path) || !File.file?(path)
      rel = Pathname.new(path).relative_path_from(@root).to_s
      next unless Intake.audio?(rel) || Intake.archive?(rel)
      yield rel, File.stat(path)
    rescue SystemCallError => e
      @log.warn "[IntakeWatcher] #{path}: #{e.message}"
    end
  end

  def unit_of(rel)
    dirs = rel.split("/")[0...-1]
    dirs.first(DEPTH.fetch(@name, 1)).join("/").presence || "."
  end

  def queue(unit, files)
    batch = IntakeBatch.create!(user: @user, name: "#{@name}: #{unit == '.' ? 'loose files' : unit}".first(250),
                                source: "watch:#{@name}")
    taken = files.select do |rel, _size, _mtime|
      File.open(@root.join(rel), "rb") { |io| batch.receive!(io, rel) }
      true
    rescue SystemCallError, ArgumentError => e
      @log.warn "[IntakeWatcher] #{@name}/#{rel}: #{e.message}"   # gone or unreadable: tried again next look
      false
    end
    return batch.discard! && nil if taken.empty?
    # marked as taken only once the whole batch is copied and queued: a worker stopped mid-copy leaves
    # a batch that clear_unfinished removes, and its files are taken again
    IntakeBatch.transaction do
      batch.finish_upload!
      IntakeWatchFile.upsert_all(taken.map { |rel, size, mtime|
        { watch: @name, path: rel, byte_size: size, file_mtime: mtime, intake_batch_id: batch.id, created_at: @now, updated_at: @now }
      }, unique_by: [ :watch, :path ])
    end
    batch
  end
end
