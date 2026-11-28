# Works out which MusicBrainz release and tracks a set of files is, from their tags.
#
# Files are matched as albums, the way a person would: the files of one folder that name the same
# album are compared, track by track (title and length), with every release of that name by that
# artist, and the release that explains them best wins. That picks the right pressing (the 19-track
# CD rather than the 14-track original) instead of a pile of correct-but-unrelated recordings.
# A file that fits no release is matched on its own, by artist, title and length.
#
# For each file the answer is the full set of tags MusicBrainz gives it (keys are the
# song_file_tags columns) plus "match" => { "method" =>, "score" => }, or nil when nothing fits
# well enough. A wrong match is worse than none: thresholds are deliberately strict.
class MusicbrainzMatcher
  VARIOUS_ARTISTS_GID = "89ad4ac3-39f7-470e-963a-56509c546377".freeze
  LENGTH_SLACK = 7.0        # seconds a file may differ from the track's listed length
  ALBUM_THRESHOLD = 0.8     # share of an album's files that must fit the release
  MAX_CANDIDATES = 10       # releases compared track by track per album

  def self.norm(text)
    text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
        .gsub(/[\(\[]\s*(feat|ft|featuring|with)\b[^\)\]]*[\)\]]/, " ").gsub(/\s(feat|ft|featuring)\.?\s.*\z/, " ")
        .gsub("&", " and ").gsub(/[^[:alnum:]]/, "")
  end

  def initialize(mirror)
    @mirror = mirror
    @artists = {}
    @releases = {}
  end

  # entries: [{ id:, tags: }] for files that belong together (one folder). Returns { id => tags or nil }.
  def match(entries)
    result = {}
    entries.group_by { |e| album_key(e[:tags]) }.each do |key, group|
      result.merge!(key ? match_album(group) : {})
    end
    entries.each { |e| result[e[:id]] ||= match_single(e[:tags]) }
    result
  end

  private

  def norm(text) = self.class.norm(text)

  def album_key(tags)
    return [ :release, tags["musicbrainz_release_id"] ] if tags["musicbrainz_release_id"].present?
    album = norm(tags["album"])
    album.present? ? [ :name, album, norm(tags["album_artist"].presence || tags["artist"]) ] : nil
  end

  def match_album(group)
    tags = group.first[:tags]
    candidates = if tags["musicbrainz_release_id"].present?
      [ @mirror.release(tags["musicbrainz_release_id"]) ].compact.map { |r| r.slice("id") }
    else
      wanted = norm(tags["album"])
      artist_ids = artists_for(tags["album_artist"].presence || tags["artist"]).map { |a| a["id"] }
      named = releases_for(artist_ids).select { |r| norm(r["name"]) == wanted }
      named.sort_by { |r| [ (Array(r["track_counts"]).sum - group.size).abs, r["status"] == "Official" ? 0 : 1, r["id"] ] }.first(MAX_CANDIDATES)
    end
    best = candidates.map { |c| score_release(c, group) }.max_by { |s| s[:score] }
    by_ids = tags["musicbrainz_release_id"].present?
    return {} unless best && (by_ids || best[:fit] >= ALBUM_THRESHOLD)

    details = @mirror.release_details(best[:release]["id"])
    best[:pairs].to_h do |entry, track|
      [ entry[:id], canonical(details, track, by_ids ? "ids" : "album", best[:fit]) ]
    end
  end

  # How well a release explains the files: each file is paired with the track at its disc and track
  # number (or, without numbers, the track of the same title) and counts when title and length agree.
  def score_release(release, group)
    tracks = @mirror.tracks(release["id"])
    pairs = {}
    group.each do |entry|
      t = entry[:tags]
      track = if t["musicbrainz_recording_id"].present? && tracks.any? { |x| x["recording_gid"] == t["musicbrainz_recording_id"] }
        tracks.find { |x| x["recording_gid"] == t["musicbrainz_recording_id"] && (t["track_number"].nil? || x["position"] == t["track_number"]) } ||
          tracks.find { |x| x["recording_gid"] == t["musicbrainz_recording_id"] }
      elsif t["track_number"]
        tracks.find { |x| x["position"] == t["track_number"] && x["disc"] == (t["disc_number"] || 1) }
      end
      track = nil if track && !same_song?(t, track)
      track ||= tracks.find { |x| same_song?(t, x) && !pairs.value?(x) }
      pairs[entry] = track if track
    end
    fit = pairs.size.to_f / group.size
    bonus = (tracks.size == group.size ? 0.05 : 0) + (release["status"] == "Official" ? 0.02 : 0) +
            (media_agrees?(group.first[:tags], release) ? 0.03 : 0)
    { release: release, pairs: pairs, fit: fit, score: fit + bonus }
  end

  def same_song?(tags, track)
    return false unless norm(tags["title"]) == norm(track["name"])
    close_enough?(tags["duration_seconds"], track["length"])
  end

  def close_enough?(seconds, milliseconds)
    return true if seconds.to_f.zero? || milliseconds.to_i.zero?
    (seconds.to_f - milliseconds / 1000.0).abs <= LENGTH_SLACK
  end

  def media_agrees?(tags, release)
    media = release["media"].to_s.downcase
    wanted = tags["media"].to_s.downcase
    wanted.present? && media.present? && (media.include?(wanted) || wanted.include?(media))
  end

  # One file on its own: the artist's recording of that title and length. When the file names an
  # album and the recording is on a release of that name, the file gets that release too.
  def match_single(tags)
    title = norm(tags["title"])
    return nil if title.blank?
    artist_ids = artists_for(tags["artist"]).map { |a| a["id"] }
    found = @mirror.recordings_by_artists(artist_ids).select { |r| norm(r["name"]) == title && close_enough?(tags["duration_seconds"], r["length"]) }
    # no length to go on and several different recordings of that title: cannot tell them apart
    return nil if found.empty? || (tags["duration_seconds"].to_f.zero? && found.size > 1)
    recording = found.min_by { |r| [ r["length"] ? (tags["duration_seconds"].to_f - r["length"] / 1000.0).abs : LENGTH_SLACK, r["id"] ] }
    describe(recording, tags, "recording")
  end

  public

  # A file identified by its sound (AcoustID gave the recording): the release is the one the file's
  # album tag names, when MusicBrainz has the recording on it. nil when the mirror has no such recording,
  # or its length is far from the file's.
  def match_recording(gid, tags)
    recording = @mirror.recording(gid)
    return nil unless recording && close_enough?(tags["duration_seconds"], recording["length"])
    describe(recording, tags, "fingerprint")
  end

  private

  def describe(recording, tags, method)
    if tags["album"].present?
      release = @mirror.releases_of_recording(recording["id"])
                       .select { |r| norm(r["name"]) == norm(tags["album"]) }
                       .min_by { |r| [ r["status"] == "Official" ? 0 : 1, r["id"] ] }
      if release
        track = @mirror.tracks(release["id"]).find { |t| t["recording_gid"] == recording["gid"] }
        return canonical(@mirror.release_details(release["id"]), track, method == "fingerprint" ? "fingerprint" : "track", 1.0) if track
      end
    end
    credit = @mirror.recording_credit(recording["id"])
    { "title" => recording["name"], "artist" => credit["credit"], "musicbrainz_recording_id" => recording["gid"],
      "musicbrainz_artist_ids" => credit["artists"].map { |a| a["gid"] }, "artist_sort" => sort_names(credit["artists"]),
      "match" => { "method" => method, "score" => 1.0 } }
  end

  def canonical(release, track, method, score)
    date = [ release["date_year"], release["date_month"], release["date_day"] ].take_while(&:present?)
                                                                              .each_with_index.map { |v, i| format(i.zero? ? "%04d" : "%02d", v) }.join("-")
    {
      "title" => track["name"], "artist" => track["credit"], "artist_sort" => sort_names(track["artists"]),
      "musicbrainz_artist_ids" => track["artists"].map { |a| a["gid"] },
      "album" => release["name"], "album_artist" => release["artist_credit"], "album_artist_sort" => sort_names(release["artists"]),
      "musicbrainz_album_artist_ids" => release["artists"].map { |a| a["gid"] },
      "track_number" => track["position"], "track_total" => track["track_count"],
      "disc_number" => track["disc"], "disc_total" => release["disc_total"],
      "date_raw" => date.presence, "year" => release["date_year"], "original_date_raw" => release["original_release_year"]&.to_s,
      "release_type" => [ release["release_type"], release["secondary_types"] ].compact_blank.join("; ").presence,
      "release_status" => release["release_status"]&.downcase, "release_country" => release["release_country"],
      "label" => release["label"], "catalog_number" => release["catalog_number"], "barcode" => release["barcode"],
      "media" => track["media"], "compilation" => release["artists"].any? { |a| a["gid"] == VARIOUS_ARTISTS_GID },
      "musicbrainz_recording_id" => track["recording_gid"], "musicbrainz_release_id" => release["gid"],
      "musicbrainz_release_group_id" => release["musicbrainz_release_group_id"], "musicbrainz_release_track_id" => track["track_gid"],
      "match" => { "method" => method, "score" => score.round(2) }
    }
  end

  def sort_names(artists) = artists.map { |a| a["sort_name"] }.compact.join("; ").presence

  # The artist(s) of that name; for a credit like "A feat. B" or "A & B", the first name in it.
  def artists_for(name)
    return [] if name.blank?
    @artists[name] ||= begin
      found = @mirror.artists_named(name)
      first = name.split(/\s+(?:feat\.?|ft\.?|featuring|with|x|&|and)\s+|[,;\/]/i).first.to_s.strip
      found = @mirror.artists_named(first) if found.empty? && first.present? && first != name
      found
    end
  end

  def releases_for(artist_ids)
    @releases[artist_ids] ||= @mirror.releases_by_artists(artist_ids)
  end
end
