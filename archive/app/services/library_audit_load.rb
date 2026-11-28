# Loads measurements of the whole library, made by the library audit (library_tools/audit/scan.py and
# export_measurements.py), into song_measurements, so the Drop Box compares new files with every
# stored song. A measurement is taken only when the song's stored file is still the one measured
# (same checksum) and the song has none yet: what the Drop Box measured itself is never replaced.
#
# It also records the audit's quality issues (broken, flawed, low fidelity): the wanted list on the
# Library quality page. It hides nothing and merges nothing.
class LibraryAuditLoad
  COLUMNS = %w[song_id blob_checksum measure_version score_version verdict quality codec kbps lossless bits sample_rate
               eff_khz duration loudness_lufs problems notes data fingerprint fingerprint_keys measured_at].freeze

  def initialize(path, log: Rails.logger)
    @path = path
    @log = log
  end

  def run
    conn = ActiveRecord::Base.connection
    conn.transaction do
      conn.execute(<<~SQL)
        create temporary table audit_load (
          song_id uuid, blob_checksum varchar, measure_version int, score_version int, verdict varchar, quality int,
          codec varchar, kbps int, lossless boolean, bits int, sample_rate int, eff_khz float, duration float,
          loudness_lufs float, problems jsonb, notes jsonb, data jsonb, fingerprint bytea, fingerprint_keys int[],
          measured_at timestamp) on commit drop
      SQL
      raw = conn.raw_connection
      raw.copy_data("copy audit_load (#{COLUMNS.join(', ')}) from stdin") do
        File.foreach(@path) { |line| raw.put_copy_data(line) }
      end
      read = conn.select_value("select count(*) from audit_load").to_i
      added = conn.exec_update(<<~SQL)
        insert into song_measurements (id, song_id, blob_checksum, measure_version, score_version, verdict, quality, codec,
          kbps, lossless, bits, sample_rate, eff_khz, duration, loudness_lufs, problems, notes, data, fingerprint,
          fingerprint_keys, measured_at, created_at, updated_at)
        select gen_random_uuid(), l.song_id, l.blob_checksum, l.measure_version, l.score_version, l.verdict, l.quality, l.codec,
          l.kbps, l.lossless, l.bits, l.sample_rate, l.eff_khz, l.duration, l.loudness_lufs, l.problems, l.notes, l.data,
          l.fingerprint, l.fingerprint_keys, coalesce(l.measured_at, now()), now(), now()
        from audit_load l
        join songs s on s.id = l.song_id
        join active_storage_attachments a on a.record_type = 'Song' and a.name = 'audio_file' and a.record_id = s.id
        join active_storage_blobs b on b.id = a.blob_id and b.checksum = l.blob_checksum
        where not exists (select 1 from song_measurements m where m.song_id = l.song_id)
      SQL
      issues = conn.exec_update(<<~SQL)
        insert into song_issues (id, song_id, kind, source, detail, created_at, updated_at)
        select gen_random_uuid(), m.song_id,
               case m.verdict when 'bad' then 'broken' when 'flawed' then 'flawed' else 'low_fidelity' end,
               'audit', jsonb_build_object('problems', m.problems, 'quality', m.quality), now(), now()
        from song_measurements m
        where m.verdict in ('bad', 'flawed', 'weak')
          and not exists (select 1 from song_issues i where i.song_id = m.song_id and i.resolved_at is null
                          and i.kind in ('broken', 'flawed', 'low_fidelity'))
      SQL
      @log.info "read #{read} measurements; added #{added} (others: song gone, file changed since, or already measured); #{issues} quality issues recorded"
    end
  end
end
