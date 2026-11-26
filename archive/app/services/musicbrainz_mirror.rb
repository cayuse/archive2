# Read-only queries against the local MusicBrainz mirror (a Postgres database, MUSICBRAINZ_URL).
# Every query goes through an index: by gid, by artist name (the mirror's lower/unaccent index) or
# by a row id found that way. Nothing here scans a MusicBrainz table.
#
# The mirror is a help and never a requirement: callers treat any error as "not found".
class MusicbrainzMirror
  def self.configured? = ENV["MUSICBRAINZ_URL"].present?
  def self.default = configured? ? new(ENV["MUSICBRAINZ_URL"]) : nil

  def initialize(url)
    @url = url
  end

  def close
    @conn&.close
    @conn = nil
  end

  # --- single rows by MusicBrainz id, following merges (gid redirects) ---

  def artist(gid)
    rows(<<~SQL, [ gid ]).first
      select a.gid, a.name, a.sort_name, nullif(a.comment, '') as disambiguation, t.name as type
      from (select id from artist where gid = $1 union select new_id from artist_gid_redirect where gid = $1) x
      join artist a on a.id = x.id left join artist_type t on t.id = a.type
    SQL
  end

  def recording(gid)
    rows(<<~SQL, [ gid ]).first
      select r.gid, r.name, r.length
      from (select id from recording where gid = $1 union select new_id from recording_gid_redirect where gid = $1) x
      join recording r on r.id = x.id
    SQL
  end

  # The release as LibraryImporter fills an album from it (keys are albums columns).
  def release(gid)
    row = rows("select id from release where gid = $1 union select new_id from release_gid_redirect where gid = $1", [ gid ]).first
    row && release_details(row["id"])
  end

  # --- searching ---

  def artists_named(name)
    rows(<<~SQL, [ name ])
      select a.id, a.gid, a.name, a.sort_name from artist a
      where lower(musicbrainz_unaccent(a.name)) = lower(musicbrainz_unaccent($1)) limit 20
    SQL
  end

  # Every release an artist is credited on: id, gid, name, how many tracks on each disc and the format.
  def releases_by_artists(artist_ids)
    return [] if artist_ids.empty?
    rows(<<~SQL, [ "{#{artist_ids.map(&:to_i).join(',')}}" ])
      select r.id, r.gid, r.name, rs.name as status,
             (select array_agg(m.track_count order by m.position) from medium m where m.release = r.id) as track_counts,
             (select string_agg(distinct mf.name, ', ') from medium m join medium_format mf on mf.id = m.format where m.release = r.id) as media
      from (select distinct r.id from artist_credit_name acn join release r on r.artist_credit = acn.artist_credit
            where acn.artist = any($1::int[]) limit 5000) x
      join release r on r.id = x.id left join release_status rs on rs.id = r.status
    SQL
  end

  # Recordings an artist is credited on (the caller compares titles: spelling in MusicBrainz varies in
  # case, apostrophes and accents, which an exact SQL match would miss).
  def recordings_by_artists(artist_ids, limit: 5000)
    return [] if artist_ids.empty?
    rows(<<~SQL, [ "{#{artist_ids.map(&:to_i).join(',')}}", limit ])
      select distinct r.id, r.gid, r.name, r.length from artist_credit_name acn
      join recording r on r.artist_credit = acn.artist_credit where acn.artist = any($1::int[]) limit $2
    SQL
  end

  def recording_credit(recording_id)
    row = rows("select ac.id as credit_id, ac.name as credit from recording r join artist_credit ac on ac.id = r.artist_credit where r.id = $1", [ recording_id ]).first
    row.merge("artists" => credit_artists([ row["credit_id"] ])[row["credit_id"]] || [])
  end

  # Releases a recording appears on, with where it sits on each.
  def releases_of_recording(recording_id)
    rows(<<~SQL, [ recording_id ])
      select r.id, r.gid, r.name, rs.name as status from track t join medium m on m.id = t.medium
      join release r on r.id = m.release left join release_status rs on rs.id = r.status
      where t.recording = $1 limit 300
    SQL
  end

  # Tracks of a release in order: disc, position, title, length (ms), ids and the credited artists.
  def tracks(release_id)
    tracks = rows(<<~SQL, [ release_id ])
      select m.position as disc, m.track_count, mf.name as media, t.position, t.name, t.length, t.gid as track_gid,
             rec.gid as recording_gid, ac.id as credit_id, ac.name as credit
      from medium m join track t on t.medium = m.id join recording rec on rec.id = t.recording
      join artist_credit ac on ac.id = t.artist_credit left join medium_format mf on mf.id = m.format
      where m.release = $1 and t.position > 0 order by m.position, t.position
    SQL
    credits = credit_artists(tracks.map { |t| t["credit_id"] })
    tracks.each { |t| t["artists"] = credits[t["credit_id"]] || [] }
  end

  # artist_credit id => [{gid, name, sort_name}, ...] in credit order
  def credit_artists(credit_ids)
    ids = credit_ids.compact.uniq
    return {} if ids.empty?
    rows(<<~SQL, [ "{#{ids.map(&:to_i).join(',')}}" ]).group_by { |r| r["credit_id"] }
      select acn.artist_credit as credit_id, a.gid, a.name, a.sort_name from artist_credit_name acn
      join artist a on a.id = acn.artist where acn.artist_credit = any($1::int[]) order by acn.artist_credit, acn.position
    SQL
  end

  def release_details(release_id)
    row = rows(<<~SQL, [ release_id ]).first
      select r.id, r.gid, r.name, nullif(r.barcode, '') as barcode, rs.name as release_status, ac.id as credit_id, ac.name as artist_credit,
             rg.gid as musicbrainz_release_group_id, lower(pt.name) as release_type,
             (select lower(string_agg(st.name, '; ' order by st.name)) from release_group_secondary_type_join j
                join release_group_secondary_type st on st.id = j.secondary_type where j.release_group = rg.id) as secondary_types,
             (select first_release_date_year from release_group_meta where id = rg.id) as original_release_year,
             (select count(*) from medium m where m.release = r.id) as disc_total,
             (select sum(m.track_count) from medium m where m.release = r.id) as total_tracks,
             d.date_year, d.date_month, d.date_day, d.country as release_country, l.name as label, l.catalog_number
      from release r join release_group rg on rg.id = r.release_group join artist_credit ac on ac.id = r.artist_credit
      left join release_status rs on rs.id = r.status left join release_group_primary_type pt on pt.id = rg.type
      left join lateral (
        select e.date_year, e.date_month, e.date_day, e.country from (
          select rc.date_year, rc.date_month, rc.date_day, i.code as country from release_country rc
            left join iso_3166_1 i on i.area = rc.country where rc.release = r.id
          union all select date_year, date_month, date_day, null from release_unknown_country where release = r.id) e
        order by e.date_year nulls last, e.date_month nulls last, e.date_day nulls last limit 1) d on true
      left join lateral (
        select lb.name, nullif(rl.catalog_number, '') as catalog_number from release_label rl
          left join label lb on lb.id = rl.label where rl.release = r.id order by rl.id limit 1) l on true
      where r.id = $1
    SQL
    return nil unless row
    row["artists"] = credit_artists([ row["credit_id"] ])[row["credit_id"]] || []
    row["release_year"] = row["date_year"]
    row
  end

  private

  def conn
    @conn ||= PG.connect(@url, connect_timeout: 5).tap do |c|
      registry = PG::BasicTypeRegistry.new.register_default_types
      registry.alias_type(0, "uuid", "text")
      c.type_map_for_results = PG::BasicTypeMapForResults.new(c, registry: registry)
      c.exec("set default_transaction_read_only = on; set search_path = musicbrainz, public; set statement_timeout = '15s'")
    end
  end

  def rows(sql, params)
    conn.exec_params(sql, params).to_a
  rescue PG::ConnectionBad, PG::UnableToSend
    close
    raise
  end
end
