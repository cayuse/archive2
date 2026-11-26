# Reads the tags of a song's stored file and files the song by them (LibraryImporter): the same
# rules the Drop Box follows. Used by the API upload and by "process again" on the Maintenance
# page. It does not change the file; identifying against MusicBrainz and rewriting tags is the
# Drop Box's job (IntakeProcessor).
class AudioFileProcessingJob < ApplicationJob
  queue_as :default

  def perform(song_id)
    song = Song.find_by(id: song_id)
    return unless song&.audio_file&.attached?
    return if song.processing_in_progress? || song.processing_completed?

    song.update_columns(processing_status: "processing", processing_error: nil)
    song.audio_file.blob.open do |file|
      tags = TagScanner.scan(file.path)
      raise tags["scan_error"] if tags["scan_error"].present?
      record = song.file_tag || song.build_file_tag
      record.update!(tags.slice(*SongFileTag.column_names).except("id", "song_id").merge(
        blob_key: song.audio_file.key, blob_checksum: song.audio_file.checksum, scanned_at: Time.current))
      extension = File.extname(song.audio_file.filename.to_s).delete(".").downcase
      song.file_format ||= extension if Intake.audio?("x.#{extension}") && !%w[oga opus].include?(extension)
      song.file_size ||= song.audio_file.byte_size
      mirror = MusicbrainzMirror.default
      LibraryImporter.new(song, tags, musicbrainz: mirror).apply!
      mirror&.close
    end
  rescue StandardError => e
    Rails.logger.error "AudioFileProcessingJob failed for song #{song_id}: #{e.class}: #{e.message}"
    song&.update_columns(processing_status: "failed", processing_error: e.message.first(500))
  end
end
