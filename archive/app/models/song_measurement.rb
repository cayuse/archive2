# The audit of one song's stored file (lib/audio_audit, run by AudioAudit): its verdict, the numbers
# behind it, and its Chromaprint fingerprint. See docs/reference/LIBRARY_QUALITY.md.
#
# fingerprint       raw Chromaprint of the first 120 s: little-endian uint32 values, about 8 a second
# fingerprint_keys  a sample of those values as signed int4, GIN-indexed: the first step in finding
#                   other copies of the same recording (Fingerprint.candidates)
class SongMeasurement < ApplicationRecord
  VERDICTS = %w[ok weak flawed bad].freeze

  belongs_to :song

  validates :verdict, inclusion: { in: VERDICTS }

  def fingerprint_values = fingerprint.present? ? fingerprint.unpack("V*") : []

  def fingerprint_values=(values)
    self.fingerprint = values.pack("V*")
    self.fingerprint_keys = Fingerprint.keys(values)
  end

  # Attributes from the JSON lib/audio_audit/cli.py prints.
  def self.attributes_from(json, blob_checksum: nil)
    ev = json.fetch("evaluation")
    m = json["measurements"] || {}
    bits, rate = Array(ev["res"])
    attrs = {
      blob_checksum: blob_checksum, measure_version: json["measure_version"], score_version: json["score_version"],
      verdict: ev["verdict"], quality: ev["quality"], codec: ev["codec"], kbps: ev["kbps"], lossless: !!ev["lossless"],
      bits: (bits if ev["lossless"]), sample_rate: (rate if ev["lossless"]), eff_khz: ev["eff_khz"],
      duration: m.dig("signal", "decoded_dur") || m.dig("probe", "audio_dur"),
      loudness_lufs: m.dig("loudness", "I"),
      problems: Array(ev["problems"]).map { |level, text| { "level" => level, "text" => text } },
      notes: Array(ev["notes"]), data: m, acoustid_fingerprint: json.dig("acoustid", "fingerprint"),
      measured_at: Time.current
    }
    if json["fingerprint"].present?
      values = Base64.decode64(json["fingerprint"]).unpack("V*")
      attrs.merge!(fingerprint: values.pack("V*"), fingerprint_keys: Fingerprint.keys(values))
    end
    attrs
  end
end
