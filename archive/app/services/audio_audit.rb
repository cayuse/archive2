# Measures and judges one audio file with lib/audio_audit (Python: ffmpeg, mp3val, flac, fpcalc,
# numpy) and keeps the result as the song's SongMeasurement. The same code measured the whole library
# (library_tools/audit), so a new file's numbers compare directly with every stored song's.
module AudioAudit
  CLI = Rails.root.join("lib", "audio_audit", "cli.py").to_s
  class Error < StandardError; end

  module_function

  # The parsed JSON for a file on disk. Raises AudioAudit::Error when it cannot be measured.
  def measure(path, format = nil)
    # each ffmpeg / fpcalc run inside has its own time limit (measure.py TIMEOUT), so this returns
    out, err, status = Open3.capture3("python3", "-I", CLI, path.to_s, *[ format ].compact)
    json = JSON.parse(out.presence || "{}")
    raise Error, json["error"] || err.lines.last.to_s.strip.presence || "no result" unless status.success? && json["evaluation"]
    json
  rescue JSON::ParserError
    raise Error, "unreadable result: #{err.to_s.lines.last.to_s.strip}"
  end

  # Measures +path+ (the song's file, or a copy of it) and saves the measurement on the song.
  def measure_song!(song, path, json: nil)
    json ||= measure(path, song.file_format)
    checksum = song.audio_file.attached? ? song.audio_file.blob.checksum : nil
    record = song.measurement || song.build_measurement
    record.update!(SongMeasurement.attributes_from(json, blob_checksum: checksum))
    record
  end
end
