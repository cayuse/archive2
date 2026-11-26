# Files one song into the library from the tags read out of its file: finds or creates its artist,
# album artist, album, genre and artist credits, and fills in the song. Every path that adds or
# re-reads a song goes through here, so the rules live in one place. They are the rules the
# repaired library follows (LibraryRebuilder is the batch version; see
# library_tools/IMPORTER_FIX_PLAN.md):
#
#   * Tag values are never rewritten. Whitespace is trimmed, nothing else.
#   * A tag wins over what the database holds; where the file has no tag, the database value stays.
#   * Artist: by MusicBrainz artist id when the file has one. Otherwise by name, ignoring case;
#     a name that belongs to exactly one MusicBrainz artist we already hold uses that row.
#   * Album artist: the album-artist tag (or its id); "Various Artists" for a compilation with no
#     album-artist tag; otherwise the song's artist.
#   * Album: by MusicBrainz release id when the file has one. Otherwise by album artist + title,
#     ignoring case. Never by title alone.
#   * Genre: matched ignoring case and punctuation, so "Hip Hop" and "Hip-Hop" are one genre.
#   * No placeholder rows ("Unknown Album"). What the file does not say stays empty.
#
# +tags+ is a hash with the song_file_tags columns as keys (TagScanner.scan). +musicbrainz+ is an
# optional lookup object answering artist(gid), release(gid) and recording(gid) with a hash or nil;
# without it (or when it fails) the tag values are used as they are.
class LibraryImporter
  VARIOUS_ARTISTS = "Various Artists".freeze
  ALBUM_FIELDS = { "musicbrainz_release_group_id" => "musicbrainz_release_group_id", "release_year" => "year",
                   "release_type" => "release_type", "release_status" => "release_status",
                   "release_country" => "release_country", "label" => "label", "catalog_number" => "catalog_number",
                   "barcode" => "barcode", "disc_total" => "disc_total", "total_tracks" => "track_total",
                   "sort_title" => "album_sort" }.freeze

  def self.name_key(value) = value.to_s.strip.downcase.presence
  def self.genre_key(value) = value.to_s.downcase.gsub(/[^[:alnum:]]/, "").presence

  def initialize(song, tags, musicbrainz: nil)
    @song = song
    @tags = tags.to_h.transform_keys(&:to_s)
    @mb = musicbrainz
  end

  # Returns the song, saved. Its status is "completed" when it has a title and an artist,
  # otherwise "needs_review".
  def apply!
    Song.transaction do
      credits = credited_artists
      artist = credits.first || artist_named(tag("artist"))
      album = find_album(artist)

      @song.title = tag("title").first(200) if tag("title")
      @song.artist = artist if artist
      @song.album = album if album
      @song.genre = find_genre || @song.genre
      @song.artist_credit = tag("artist") if tag("artist")
      @song.track_number = positive("track_number") || @song.track_number
      @song.disc_number = positive("disc_number") || @song.disc_number
      seconds = @tags["duration_seconds"].to_f.round
      @song.duration = seconds if seconds.positive?
      recording = uuid("musicbrainz_recording_id")
      @song.musicbrainz_recording_id = lookup(:recording, recording)&.dig("gid") || recording if recording
      @song.musicbrainz_release_track_id = uuid("musicbrainz_release_track_id") || @song.musicbrainz_release_track_id
      @song.processing_status = @song.title.present? && @song.artist ? "completed" : "needs_review"
      @song.processing_error = nil
      @song.save!
      write_credits(credits) if credits.any?
    end
    @song
  end

  private

  def tag(name) = @tags[name].to_s.strip.presence
  def uuid(name) = @tags[name].to_s.downcase[/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/]
  def uuids(name) = Array(@tags[name]).filter_map { |v| v.to_s.downcase[/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/] }.uniq

  def positive(name)
    value = @tags[name].to_i
    value if value.positive?
  end

  # MusicBrainz is a help, never a requirement: any failure means "not found".
  def lookup(kind, gid)
    return nil unless @mb && gid
    @mb.public_send(kind, gid)&.transform_keys(&:to_s)
  rescue StandardError => e
    Rails.logger.warn "[LibraryImporter] MusicBrainz #{kind} #{gid}: #{e.class}: #{e.message}"
    nil
  end

  def retrying
    yield
  rescue ActiveRecord::RecordNotUnique
    yield   # someone else created the row between our look and our insert; the second look finds it
  end

  # The artists the file credits by MusicBrainz id, in tag order. A lone id takes the artist tag as
  # its name when MusicBrainz cannot be asked; with several ids the tag is the whole credit
  # ("A feat. B"), so an id we cannot name is left out.
  def credited_artists
    ids = uuids("musicbrainz_artist_ids")
    ids.filter_map { |gid| artist_by_id(gid, fallback_name: ids.one? ? tag("artist") : nil) }.uniq
  end

  def artist_by_id(gid, fallback_name: nil)
    return nil unless gid
    found = Artist.find_by(musicbrainz_id: gid)
    return found if found
    info = lookup(:artist, gid)
    gid = info["gid"] if info&.dig("gid")   # a merged artist: MusicBrainz redirects to the one kept
    name = (info&.dig("name") || fallback_name).to_s.strip.first(200).presence
    return Artist.find_by(musicbrainz_id: gid) unless name
    retrying do
      Artist.find_by(musicbrainz_id: gid) ||
        Artist.create!(musicbrainz_id: gid, name: name, sort_name: info&.dig("sort_name"),
                       disambiguation: info&.dig("disambiguation"), artist_type: info&.dig("type"))
    end
  end

  def artist_named(name)
    key = self.class.name_key(name)
    return nil unless key
    same = Artist.where("lower(name) = ?", key).order(:created_at).to_a
    known = same.select(&:musicbrainz_id)
    return known.first if known.one?
    same.find { |a| a.musicbrainz_id.nil? } || same.first || Artist.create!(name: name.strip.first(200))
  end

  def album_artist(artist)
    artist_by_id(uuids("musicbrainz_album_artist_ids").first, fallback_name: tag("album_artist")) ||
      artist_named(tag("album_artist")) ||
      (@tags["compilation"] == true ? artist_named(VARIOUS_ARTISTS) : artist)
  end

  def find_album(artist)
    release = uuid("musicbrainz_release_id")
    info = lookup(:release, release)
    release = info["gid"] if info&.dig("gid")
    title = (tag("album") || info&.dig("name")).to_s.first(200).presence
    return nil unless title
    owner = album_artist(artist)

    album = retrying do
      if release
        Album.find_by(musicbrainz_release_id: release) || Album.create!(album_attributes(title, owner).merge(musicbrainz_release_id: release))
      else
        Album.where(artist_id: owner&.id, musicbrainz_release_id: nil).where("lower(title) = ?", title.downcase).order(:created_at).first ||
          Album.create!(album_attributes(title, owner))
      end
    end
    fill_album(album, info)
    album
  end

  def album_attributes(title, owner)
    { title: title, artist: owner, artist_credit: tag("album_artist") || owner&.name, compilation: @tags["compilation"] == true }
  end

  # Fills what the album does not know yet; never overwrites.
  def fill_album(album, info)
    ALBUM_FIELDS.each do |column, tag_name|
      next if album[column].present?
      value = info&.dig(column).presence || @tags[tag_name].presence
      album[column] = value if value
    end
    album.original_release_year ||= @tags["original_date_raw"].to_s[/\A\d{4}/]&.to_i
    album.save! if album.changed?
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[LibraryImporter] album #{album.id} details not saved: #{e.message}"
    album.reload
  end

  def find_genre
    key = self.class.genre_key(tag("genre"))
    return nil unless key
    Genre.order(:created_at).find { |g| self.class.genre_key(g.name) == key } ||
      retrying { Genre.find_by(name: tag("genre").first(100)) || Genre.create!(name: tag("genre").first(100)) }
  end

  def write_credits(artists)
    @song.song_artist_credits.where.not(artist_id: artists.map(&:id)).destroy_all
    artists.each_with_index do |artist, position|
      credit = @song.song_artist_credits.find_or_initialize_by(artist_id: artist.id)
      credit.position = position
      credit.save!
    end
  end
end
