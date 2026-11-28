# Identifies a recording by its sound: AcoustID's lookup takes a Chromaprint fingerprint (compressed,
# as fpcalc prints it) and the duration, and answers with MusicBrainz recording ids. Used by the Drop
# Box for files whose tags MusicBrainz cannot place. Only the fingerprint and the duration are sent.
#
# Needs ACOUSTID_KEY (a free application key from https://acoustid.org/new-application). Without it
# every lookup answers nil and files are filed under their own tags, as before.
class AcoustidClient
  URL = URI("https://api.acoustid.org/v2/lookup")
  MIN_SCORE = 0.85        # AcoustID's own confidence that the fingerprint is this track
  MIN_INTERVAL = 0.34     # seconds between requests: AcoustID allows three a second

  def self.default = ENV["ACOUSTID_KEY"].present? ? new(ENV["ACOUSTID_KEY"]) : nil

  def initialize(key, http: nil)
    @key = key
    @http = http
    @last = nil
  end

  # Recording ids for a fingerprint, best first (empty when AcoustID knows none with enough confidence).
  def recording_ids(fingerprint, duration)
    return [] if fingerprint.blank? || duration.to_f <= 0
    body = post(client: @key, meta: "recordingids", duration: duration.to_i, fingerprint: fingerprint)
    return [] unless body["status"] == "ok"
    Array(body["results"]).select { |r| r["score"].to_f >= MIN_SCORE }.sort_by { |r| -r["score"].to_f }
                          .flat_map { |r| Array(r["recordings"]).map { |rec| rec["id"] } }.compact.uniq
  end

  private

  def post(params)
    sleep(MIN_INTERVAL - (Time.now - @last)) if @last && Time.now - @last < MIN_INTERVAL
    @last = Time.now
    return @http.call(params) if @http
    res = Net::HTTP.post_form(URL, params)
    JSON.parse(res.body)
  rescue StandardError => e
    Rails.logger.warn "[AcoustID] #{e.class}: #{e.message}"
    {}
  end
end
