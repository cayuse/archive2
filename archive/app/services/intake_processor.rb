# Deals with one drop (IntakeBatch), start to finish. Every file ends as an IntakeItem that says
# what became of it; one bad file never stops the rest.
#
#   1. Archives are unpacked in place (zip, tar and its compressed forms, 7z, rar), safely:
#      nothing outside the batch can be written, links are discarded, size and count are capped.
#   2. Anything that is not audio is rejected and listed. Audio is confirmed by decoding its
#      headers (ffprobe), not by trusting the file name.
#   3. A file already in the library (same bytes) is a duplicate: listed, not imported.
#   4. The files of each folder are identified together against MusicBrainz (MusicbrainzMatcher).
#      A track of a release the library already holds is a duplicate too.
#   5. The tags are rewritten in the standard layout (TagWriter): MusicBrainz's values where the
#      file was identified, the file's own values otherwise. The untouched original is kept in
#      originals/ for Intake::KEEP_ORIGINALS.
#   6. The file becomes a Song: stored, its tags recorded (song_file_tags), filed by LibraryImporter.
#
# Songs arrive without audio analysis; `Song.awaiting_analysis` is the reserve the offline
# analysis run works through.
#
# Safe to run again on a batch that was interrupted: the work directory holds exactly what is
# still to do, and finished items are skipped.
class IntakeProcessor
  FORMATS = { "oga" => "ogg", "opus" => "ogg" }.freeze   # Song#file_format for extensions outside its list

  def initialize(batch, mirror: MusicbrainzMirror.default, log: Rails.logger)
    @batch = batch
    @mirror = mirror
    @log = log
  end

  def run
    FileUtils.mkdir_p(work)
    if File.directory?(@batch.incoming_dir)
      Dir.children(@batch.incoming_dir).each { |c| FileUtils.mv(@batch.incoming_dir.join(c), work.join(c)) }
      FileUtils.rm_rf(@batch.incoming_dir)
    end
    unpack_archives
    files = Dir.glob("**/*", File::FNM_DOTMATCH, base: work).select { |f| File.file?(work.join(f)) && !File.symlink?(work.join(f)) }.sort
    ready = files.filter_map { |rel| examine(rel) }
    ready.group_by { |f| File.dirname(f[:rel]) }.each_value { |folder| import_folder(folder) }
    FileUtils.rm_rf(work)
    @batch.update!(status: "done", finished_at: Time.current, error: nil)
  rescue StandardError => e
    @log.error "[Intake] batch #{@batch.id}: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
    @batch.update!(status: "done", finished_at: Time.current, error: "#{e.class}: #{e.message}")
  ensure
    @mirror&.close
  end

  private

  def work = @batch.work_dir

  def item(rel) = IntakeItem.find_or_initialize_by(intake_batch_id: @batch.id, relative_path: rel)

  def settle(rel, status, message = nil, **attrs)
    record = item(rel)
    record.update!(status: status, message: message, **attrs)
    record
  end

  # --- 1. archives ---

  def unpack_archives
    Intake::MAX_NESTING.times do
      archives = Dir.glob("**/*", base: work).select { |f| File.file?(work.join(f)) && Intake.archive?(f) }
      break if archives.empty?
      archives.each { |rel| unpack(rel) }
    end
    # an archive still packed after MAX_NESTING levels is rejected by examine as "not audio"
  end

  def unpack(rel)
    path = work.join(rel)
    size = File.size(path)
    target = work.join(rel.sub(Intake::ARCHIVES, "") + ".unpacked")
    listing, err, status = Open3.capture3("bsdtar", "-tvf", path.to_s)
    raise "cannot be read as an archive (#{err.lines.last.to_s.strip})" unless status.success?
    entries = listing.lines
    total = entries.sum { |l| l.split[4].to_i }
    raise "holds #{entries.size} entries; the limit is #{Intake::MAX_ARCHIVE_ENTRIES}" if entries.size > Intake::MAX_ARCHIVE_ENTRIES
    raise "unpacks to #{total / 1.gigabyte} GB; the limit is #{Intake::MAX_ARCHIVE_BYTES / 1.gigabyte} GB" if total > Intake::MAX_ARCHIVE_BYTES

    FileUtils.mkdir_p(target)
    # bsdtar refuses absolute paths, ".." and writing through links unless told otherwise
    _out, err, status = Open3.capture3("bsdtar", "-xf", path.to_s, "-C", target.to_s, "--no-same-owner", "--no-same-permissions")
    raise "could not be unpacked (#{err.lines.last.to_s.strip})" unless status.success?
    Dir.glob("**/*", File::FNM_DOTMATCH, base: target).each do |f|
      full = target.join(f)
      File.symlink?(full) || !(File.file?(full) || File.directory?(full)) ? FileUtils.rm_f(full) : File.chmod(File.directory?(full) ? 0o755 : 0o644, full)
    end
    keep_original(rel, move: true)
    settle(rel, "expanded", "#{entries.count { |l| !l.start_with?('d') }} files inside", byte_size: size)
  rescue StandardError => e
    FileUtils.rm_rf(target) if target
    FileUtils.rm_f(path)
    settle(rel, "rejected", "Archive #{e.message}", byte_size: size)
  end

  # --- 2 and 3. one file: is it audio, is it new? Returns what import needs, or nil when settled ---

  def examine(rel)
    path = work.join(rel)
    record = item(rel)
    return (FileUtils.rm_f(path); nil) if record.persisted? && record.status != "received"   # settled in an interrupted run
    size = File.size(path)
    reason = not_wanted(rel, path, size)
    return (settle(rel, "rejected", reason, byte_size: size); FileUtils.rm_f(path); nil) if reason

    checksum = Digest::MD5.file(path).base64digest
    if (song = existing_song(checksum))
      settle(rel, "duplicate", "Already in the library (identical file)", byte_size: size, checksum: checksum, song: song)
      FileUtils.rm_f(path)
      return nil
    end
    tags = TagScanner.scan(path)
    raise "unreadable (#{tags['scan_error']})" if tags["scan_error"].present?
    settle(rel, "received", nil, byte_size: size, checksum: checksum)
    { rel: rel, path: path, tags: tags, checksum: checksum }
  rescue StandardError => e
    settle(rel, "failed", e.message.first(500), byte_size: size)
    FileUtils.rm_f(path)
    nil
  end

  def not_wanted(rel, path, size)
    ext = File.extname(rel).delete(".").downcase
    return "Empty file" if size.zero?
    return "Not audio (#{ext.presence || 'no extension'})" unless Intake.audio?(rel)
    out, _err, status = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "stream=codec_type:stream_disposition=attached_pic",
                                       "-of", "json", path.to_s)
    streams = status.success? ? JSON.parse(out).fetch("streams", []) : []
    return "Not playable audio, whatever its name says" if streams.none? { |s| s["codec_type"] == "audio" }
    return "A video file" if streams.any? { |s| s["codec_type"] == "video" && s.dig("disposition", "attached_pic") != 1 }
    nil
  end

  # A song whose stored file, or whose file as it was first dropped, has these bytes.
  def existing_song(checksum)
    Song.joins(audio_file_attachment: :blob).find_by(active_storage_blobs: { checksum: checksum }) ||
      IntakeItem.where(checksum: checksum, status: "imported").where.not(song_id: nil).first&.song
  end

  # --- 4 to 6. a folder's worth of new audio ---

  def import_folder(folder)
    matches = begin
      @mirror ? MusicbrainzMatcher.new(@mirror).match(folder.map { |f| { id: f[:rel], tags: f[:tags] } }) : {}
    rescue StandardError => e
      @log.warn "[Intake] MusicBrainz unavailable for #{File.dirname(folder.first[:rel])}: #{e.class}: #{e.message}"
      {}
    end
    folder.each { |file| import(file, matches[file[:rel]]) }
  end

  def import(file, match)
    rel, path = file[:rel], file[:path]
    if match && (song = same_track_in_library(match))
      settle(rel, "duplicate", "This track of this release is already in the library", song: song,
             identified: match.dig("match", "method"), match_score: match.dig("match", "score"))
      return
    end
    # MusicBrainz's values where it knows the file; what MusicBrainz does not describe (genre, composer,
    # language) stays as the file had it
    wanted = file[:tags].merge(match.to_h.except("match").compact)
    keep_original(rel, move: false)
    note = retag(path, wanted)

    # stored first and outright: inside the transaction Active Storage would put off the upload until
    # commit, by which time the file is closed
    blob = File.open(path, "rb") do |io|
      ActiveStorage::Blob.create_and_upload!(io: io, filename: File.basename(rel), content_type: Marcel::MimeType.for(Pathname.new(path)), identify: false)
    end
    song = Song.transaction do
      created = Song.create!(title: wanted["title"].presence&.first(200) || File.basename(rel, ".*").first(200), user: @batch.user,
                             original_filename: File.basename(rel).first(255), processing_status: "processing",
                             file_format: format_of(rel), file_size: File.size(path))
      created.audio_file.attach(blob)
      final = TagScanner.scan(path)
      created.create_file_tag!(final.slice(*SongFileTag.column_names).except("id", "song_id").merge(
        blob_key: blob.key, blob_checksum: blob.checksum, scanned_at: Time.current))
      LibraryImporter.new(created, final, musicbrainz: @mirror).apply!
    end
    identified = match ? match.dig("match", "method") : "tags"
    note ||= "Not found in MusicBrainz; filed under the file's own tags" unless match
    settle(rel, "imported", note, song: song, identified: identified, match_score: match&.dig("match", "score"))
  rescue StandardError => e
    @log.error "[Intake] #{rel}: #{e.class}: #{e.message}"
    blob&.purge if blob && !blob.attachments.exists?
    settle(rel, "failed", "#{e.class.name.demodulize}: #{e.message}".first(500))
  ensure
    FileUtils.rm_f(path)
  end

  def same_track_in_library(match)
    return nil unless match["musicbrainz_recording_id"] && match["musicbrainz_release_id"]
    Song.joins(:album).find_by(musicbrainz_recording_id: match["musicbrainz_recording_id"],
                               albums: { musicbrainz_release_id: match["musicbrainz_release_id"] })
  end

  # Returns a note for the item when the tags could not be rewritten (the file is imported as it came).
  def retag(path, wanted)
    TagWriter.write(path, wanted) == :unsupported ? "Tags not rewritten: this format has no tag standard" : nil
  rescue TagWriter::Error => e
    "Tags not rewritten (#{e.message}); the file was stored as it arrived"
  end

  def format_of(rel)
    ext = File.extname(rel).delete(".").downcase
    FORMATS.fetch(ext, ext)
  end

  def keep_original(rel, move:)
    target = @batch.originals_dir.join(rel)
    FileUtils.mkdir_p(target.dirname)
    move ? FileUtils.mv(work.join(rel), target) : FileUtils.cp(work.join(rel), target)
  end
end
