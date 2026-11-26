# Reads the tags embedded in one audio file, by running lib/tag_scanner/scan_tags.py (mutagen).
# Returns a hash whose keys are the song_file_tags columns. The scanner never raises on a bad
# file: it sets "scan_error" instead.
class TagScanner
  SCRIPT = Rails.root.join("lib/tag_scanner/scan_tags.py").to_s
  class Error < StandardError; end

  def self.scan(path)
    out, err, status = Open3.capture3("python3", SCRIPT, "--file", path.to_s)
    raise Error, "tag scanner failed: #{err.to_s.lines.last.to_s.strip.presence || status.to_s}" unless status.success?
    JSON.parse(out)
  rescue JSON::ParserError, SystemCallError => e
    raise Error, "tag scanner failed: #{e.message}"
  end
end
