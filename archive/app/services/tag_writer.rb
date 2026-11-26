# Rewrites a file's tags in one standard layout (lib/tag_scanner/write_tags.py) and proves the
# music itself was not touched: the decoded audio is hashed before and after, and on any
# difference or error the original file is put back.
class TagWriter
  SCRIPT = Rails.root.join("lib/tag_scanner/write_tags.py").to_s
  # The fields written. Technical facts about the file (bitrate, duration) are not tags.
  FIELDS = %w[title artist album album_artist composer genre track_number track_total disc_number disc_total
              date_raw original_date_raw compilation artist_sort album_artist_sort album_sort label catalog_number
              barcode isrc asin media release_type release_status release_country language script
              musicbrainz_recording_id musicbrainz_release_id musicbrainz_release_group_id musicbrainz_release_track_id
              musicbrainz_work_id musicbrainz_artist_ids musicbrainz_album_artist_ids acoustid_id].freeze
  class Error < StandardError; end

  # Returns :written, or :unsupported for a format whose tags are left alone. Raises Error (with the
  # file restored) if anything goes wrong.
  def self.write(path, tags)
    path = path.to_s
    backup = "#{path}.before-tagging"
    before = audio_digest(path)
    FileUtils.cp(path, backup)
    Tempfile.create([ "tags", ".json" ]) do |json|
      json.write(tags.slice(*FIELDS).compact.to_json)
      json.flush
      _out, err, status = Open3.capture3("python3", SCRIPT, path, json.path)
      return :unsupported if status.exitstatus == 3
      raise Error, "tag writer failed: #{err.to_s.lines.last.to_s.strip}" unless status.success?
    end
    raise Error, "the audio changed while writing tags" unless audio_digest(path) == before
    :written
  rescue StandardError => e
    FileUtils.mv(backup, path) if File.exist?(backup)
    raise e.is_a?(Error) ? e : Error.new(e.message)
  ensure
    FileUtils.rm_f(backup)
  end

  # A hash of the decoded first audio stream: the same before and after a tag-only change.
  def self.audio_digest(path)
    out, err, status = Open3.capture3("ffmpeg", "-v", "error", "-nostdin", "-i", path.to_s, "-map", "0:a:0", "-f", "md5", "-")
    raise Error, "cannot decode audio: #{err.to_s.lines.last.to_s.strip}" unless status.success? && out.start_with?("MD5=")
    out.strip
  end
end
