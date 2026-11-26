# Rebuilds artists, albums, genres and the songs' links to them from the tags read out of the
# audio files (song_file_tags), using MusicBrainz lookup files only for ids that the tags carry.
#
# Why this exists: the original importer stripped "-" and "_" from tag values, read only five
# tags, and keyed albums by title alone. See IMPORTER_ROOT_CAUSE.md.
#
# Rules:
#   * A value present in the file's tags wins. Where the file has no tag, the database value stays.
#   * Artists are keyed by MusicBrainz artist id when the file has one, otherwise by name.
#   * Albums are keyed by MusicBrainz release id when the file has one, otherwise by album artist + title.
#   * Existing rows are reused (ids kept) where they clearly correspond; leftovers with nothing
#     pointing at them are deleted.
#
# Everything runs as set-based SQL in ONE transaction. Model callbacks do not run, so no
# the search_vector triggers do fire.
#
# Lookup files (tab-separated, written by scripts/mb_export_lookup.sql against the mirror):
#   lookup_artist.tsv, lookup_release.tsv, lookup_recording.tsv
class LibraryRebuilder
  VARIOUS_ARTISTS = "Various Artists".freeze

  def initialize(lookup_dir:, dry_run: false, log: $stdout)
    @lookup_dir = lookup_dir
    @dry_run = dry_run
    @log = log
  end

  def call
    conn.transaction do
      prepare
      load_lookups
      rebuild_musicbrainz_artists
      index_songs
      rebuild_named_artists
      resolve_song_artists
      rebuild_genres
      rebuild_albums
      update_songs
      rebuild_credits
      cleanup
      report
      if @dry_run
        say "DRY RUN: rolling back"
        raise ActiveRecord::Rollback
      end
    end
  end

  private

  def conn = ActiveRecord::Base.connection

  def say(msg) = @log.puts(msg)

  def run(label, sql)
    n = conn.exec_update(sql)
    say format("%-58s %8d", label, n)
    n
  end

  def count(sql) = conn.select_value(sql).to_i

  def prepare
    conn.execute(<<~SQL)
      -- the old importer's clean_string, to recognise rows it created
      create function pg_temp.clean(x text) returns text language sql immutable as
      $f$ select nullif(btrim(regexp_replace(regexp_replace(x, '[_-]', ' ', 'g'), '\\s+', ' ', 'g')), '') $f$;

      create function pg_temp.genre_key(x text) returns text language sql immutable as
      $f$ select nullif(lower(regexp_replace(x, '[^[:alnum:]]', '', 'g')), '') $f$;

      create function pg_temp.safe_date(x text) returns date language plpgsql immutable as
      $f$ begin
        if x ~ '^\\d{4}-\\d{2}-\\d{2}' then return substring(x from 1 for 10)::date; end if;
        return null;
      exception when others then return null;
      end $f$;

      create temp table lk_artist (tag_gid uuid primary key, gid uuid not null, name text, sort_name text,
        disambiguation text, artist_type text, area text, begin_year int) on commit drop;
      create temp table lk_release (tag_gid uuid primary key, gid uuid not null, name text, artist_credit text,
        first_artist_gid uuid, artist_count int, release_group_gid uuid, primary_type text, secondary_types text,
        status text, barcode text, year int, month int, day int, country text, original_year int, label text,
        catalog_number text, disc_total int, track_total int) on commit drop;
      create temp table lk_recording (tag_gid uuid primary key, gid uuid not null, name text, artist_credit text,
        length int) on commit drop;
    SQL
  end

  def load_lookups
    %w[artist release recording].each do |kind|
      path = File.join(@lookup_dir, "lookup_#{kind}.tsv")
      raw = conn.raw_connection
      lines = 0
      raw.copy_data("copy lk_#{kind} from stdin") do
        File.foreach(path) { |line| raw.put_copy_data(line); lines += 1 }
      end
      say format("%-58s %8d", "loaded lookup_#{kind}.tsv", lines)
    end
    conn.execute("analyze lk_artist; analyze lk_release; analyze lk_recording;")
  end

  # One artists row per MusicBrainz artist referenced by any file, named from MusicBrainz.
  def rebuild_musicbrainz_artists
    conn.execute(<<~SQL)
      create temp table need_artist on commit drop as
      select distinct on (l.gid) l.gid, l.name, l.sort_name, l.disambiguation, l.artist_type
      from (select distinct unnest(musicbrainz_artist_ids || musicbrainz_album_artist_ids) as g from song_file_tags) t
      join lk_artist l on l.tag_gid = t.g
      order by l.gid, (l.tag_gid = l.gid) desc;

      -- reuse an existing row whose name is the MusicBrainz name (or its hyphen-stripped form)
      create temp table artist_reuse on commit drop as
      select gid, id from (
        select n.gid, a.id,
               row_number() over (partition by n.gid order by (a.name = n.name) desc, a.created_at, a.id) as r1,
               row_number() over (partition by a.id order by (a.name = n.name) desc, n.gid) as r2
        from need_artist n join artists a on a.name = n.name or a.name = pg_temp.clean(n.name)
        where a.musicbrainz_id is null or a.musicbrainz_id = n.gid) x
      where r1 = 1 and r2 = 1;
    SQL
    run "artists: existing rows given a MusicBrainz id", <<~SQL
      update artists a set musicbrainz_id = n.gid, name = n.name, sort_name = n.sort_name,
             disambiguation = n.disambiguation, artist_type = n.artist_type, updated_at = now()
      from artist_reuse r join need_artist n on n.gid = r.gid
      where a.id = r.id
    SQL
    run "artists: new MusicBrainz artists inserted", <<~SQL
      insert into artists (name, musicbrainz_id, sort_name, disambiguation, artist_type, created_at, updated_at)
      select n.name, n.gid, n.sort_name, n.disambiguation, n.artist_type, now(), now()
      from need_artist n where not exists (select 1 from artists a where a.musicbrainz_id = n.gid)
    SQL
  end

  # One row per tagged song with everything resolved that can be resolved by id.
  def index_songs
    conn.execute(<<~SQL)
      create temp table sk on commit drop as
      select t.song_id, s.album_id as old_album_id, s.artist_id as old_artist_id, s.genre_id as old_genre_id,
             ma.id as mb_artist_id, maa.id as mb_aa_id,
             nullif(btrim(t.artist), '') as artist_name,
             nullif(btrim(coalesce(t.album_artist, case when t.compilation then '#{VARIOUS_ARTISTS}' end)), '') as aa_name,
             nullif(btrim(t.album), '') as album_name,
             nullif(btrim(t.title), '') as title_name,
             lr.gid as rel_gid,
             null::uuid as artist_id, null::uuid as aa_id, null::text as akey
      from song_file_tags t
      join songs s on s.id = t.song_id
      left join lk_artist la on la.tag_gid = t.musicbrainz_artist_ids[1]
      left join artists ma on ma.musicbrainz_id = la.gid
      left join lk_artist laa on laa.tag_gid = t.musicbrainz_album_artist_ids[1]
      left join artists maa on maa.musicbrainz_id = laa.gid
      left join lk_release lr on lr.tag_gid = t.musicbrainz_release_id
      where t.scan_error is null;
      create unique index on sk (song_id);
      analyze sk;
    SQL
  end

  # Artists that only have a name (no MusicBrainz id in the file).
  def rebuild_named_artists
    conn.execute(<<~SQL)
      create temp table need_name on commit drop as
      select lower(nm) as key, mode() within group (order by nm) as name
      from (select artist_name as nm from sk where mb_artist_id is null and artist_name is not null
            union all
            select aa_name from sk where mb_aa_id is null and aa_name is not null) x
      group by 1;

      create temp table name_map (key text primary key, artist_id uuid not null) on commit drop;

      -- 1. the name belongs to exactly one MusicBrainz artist we already have
      insert into name_map
      select n.key, (array_agg(a.id))[1]
      from need_name n join artists a on lower(a.name) = n.key and a.musicbrainz_id is not null
      group by n.key having count(*) = 1;

      -- 2. an existing name-only row (exact, case-insensitive, or hyphen-stripped)
      insert into name_map
      select key, id from (
        select n.key, a.id,
               row_number() over (partition by n.key order by (a.name = n.name) desc, a.created_at, a.id) as r1,
               row_number() over (partition by a.id order by (a.name = n.name) desc, n.key) as r2
        from need_name n join artists a on a.musicbrainz_id is null
             and (lower(a.name) = n.key or lower(a.name) = lower(pg_temp.clean(n.name)))
        where not exists (select 1 from name_map m where m.key = n.key)) x
      where r1 = 1 and r2 = 1;
    SQL
    run "artists: name-only rows renamed to the tag spelling", <<~SQL
      update artists a set name = n.name, updated_at = now()
      from name_map m join need_name n on n.key = m.key
      where a.id = m.artist_id and a.musicbrainz_id is null and a.name <> n.name
    SQL
    run "artists: new name-only artists inserted", <<~SQL
      with ins as (
        insert into artists (name, created_at, updated_at)
        select n.name, now(), now() from need_name n
        where not exists (select 1 from name_map m where m.key = n.key)
        returning id, name)
      insert into name_map select lower(name), id from ins
    SQL
  end

  def resolve_song_artists
    conn.execute(<<~SQL)
      update sk set artist_id = coalesce(sk.mb_artist_id, m.artist_id, sk.old_artist_id)
      from sk k left join name_map m on m.key = lower(k.artist_name)
      where k.song_id = sk.song_id;

      update sk set aa_id = coalesce(sk.mb_aa_id, m.artist_id, sk.artist_id)
      from sk k left join name_map m on m.key = lower(k.aa_name)
      where k.song_id = sk.song_id;

      update sk set akey = case
        when rel_gid is not null then 'r:' || rel_gid
        when album_name is not null then 'n:' || coalesce(aa_id::text, '') || '/' || lower(album_name)
      end;
      create index on sk (akey);
      analyze sk;
    SQL
  end

  # Genres: merge spellings that differ only in case or punctuation ("Hip Hop" / "Hip-Hop").
  def rebuild_genres
    conn.execute(<<~SQL)
      create temp table song_genre on commit drop as
      select k.song_id, coalesce(nullif(btrim(t.genre), ''), g.name) as name, (nullif(btrim(t.genre), '') is not null) as from_tag
      from sk k join song_file_tags t on t.song_id = k.song_id left join genres g on g.id = k.old_genre_id;

      create temp table need_genre on commit drop as
      select pg_temp.genre_key(name) as key,
             coalesce(mode() within group (order by name) filter (where from_tag), mode() within group (order by name)) as name
      from song_genre where pg_temp.genre_key(name) is not null group by 1;

      create temp table genre_map (key text primary key, genre_id uuid not null) on commit drop;
      insert into genre_map
      select distinct on (n.key) n.key, g.id
      from need_genre n join genres g on pg_temp.genre_key(g.name) = n.key
      order by n.key, (g.name = n.name) desc, g.created_at, g.id;
    SQL
    run "genres: new genres inserted", <<~SQL
      with ins as (
        insert into genres (name, created_at, updated_at)
        select n.name, now(), now() from need_genre n
        where not exists (select 1 from genre_map m where m.key = n.key)
          and not exists (select 1 from genres g where g.name = n.name)
        returning id, name)
      insert into genre_map select pg_temp.genre_key(name), id from ins
    SQL
  end

  def rebuild_albums
    conn.execute(<<~SQL)
      create temp table need_album on commit drop as
      select k.akey,
             max(k.rel_gid::text)::uuid as rel_gid,
             coalesce(mode() within group (order by k.album_name), max(lr.name)) as title,
             mode() within group (order by k.aa_id) as artist_id,
             coalesce(mode() within group (order by nullif(btrim(t.album_artist), '')), max(lr.artist_credit)) as artist_credit,
             mode() within group (order by nullif(btrim(t.album_sort), '')) as sort_title,
             coalesce(mode() within group (order by t.year) filter (where t.year between 1000 and 2100), max(lr.year)) as release_year,
             mode() within group (order by pg_temp.safe_date(t.date_raw)) as release_date,
             coalesce(mode() within group (order by substring(t.original_date_raw from '^\\d{4}')::int), max(lr.original_year)) as original_release_year,
             coalesce(max(lr.release_group_gid::text)::uuid, mode() within group (order by t.musicbrainz_release_group_id)) as rg_gid,
             lower(coalesce(max(lr.primary_type), mode() within group (order by nullif(btrim(split_part(t.release_type, ';', 1)), '')))) as release_type,
             lower(max(lr.secondary_types)) as secondary_types,
             lower(coalesce(max(lr.status), mode() within group (order by t.release_status))) as release_status,
             coalesce(max(lr.country), mode() within group (order by t.release_country)) as release_country,
             coalesce(mode() within group (order by t.label), max(lr.label)) as label,
             coalesce(mode() within group (order by t.catalog_number), max(lr.catalog_number)) as catalog_number,
             coalesce(mode() within group (order by t.barcode), max(lr.barcode)) as barcode,
             nullif(coalesce(max(lr.disc_total), max(t.disc_total), max(t.disc_number)), 0) as disc_total,
             nullif(max(lr.track_total), 0) as total_tracks,
             coalesce(bool_or(t.compilation), false) as compilation,
             count(*) as songs
      from sk k
      join song_file_tags t on t.song_id = k.song_id
      left join lk_release lr on lr.tag_gid = t.musicbrainz_release_id
      where k.akey is not null
      group by k.akey;
      create unique index on need_album (akey);

      update need_album n set compilation = true
      from artists a where a.id = n.artist_id and a.name = '#{VARIOUS_ARTISTS}';

      -- old album rows still wanted as-is by songs whose file has no album tag: never reuse or change these
      create temp table album_keep on commit drop as
      select distinct old_album_id as id from sk where akey is null and old_album_id is not null
      union
      select distinct s.album_id from songs s where s.album_id is not null and not exists (select 1 from sk where sk.song_id = s.id);

      -- reuse an old album row for the new album that took most of its songs (and vice versa)
      create temp table album_map (akey text primary key, album_id uuid not null unique) on commit drop;
      insert into album_map
      select akey, old_album_id from (
        select akey, old_album_id,
               row_number() over (partition by akey order by n desc, old_album_id) as r1,
               row_number() over (partition by old_album_id order by n desc, akey) as r2
        from (select akey, old_album_id, count(*) as n from sk
              where akey is not null and old_album_id is not null
                and old_album_id not in (select id from album_keep)
              group by 1, 2) c) x
      where r1 = 1 and r2 = 1
        and not exists (select 1 from albums a where a.id <> x.old_album_id
                        and a.musicbrainz_release_id = (select rel_gid from need_album n where n.akey = x.akey));
    SQL
    cols = %w[title artist_id artist_credit sort_title release_year release_date original_release_year
              musicbrainz_release_id musicbrainz_release_group_id release_type secondary_types release_status
              release_country label catalog_number barcode disc_total total_tracks compilation]
    src = "n.title, n.artist_id, n.artist_credit, n.sort_title, n.release_year, " \
          "case when n.release_date >= date '1900-01-01' then n.release_date end, n.original_release_year, " \
          "n.rel_gid, n.rg_gid, n.release_type, n.secondary_types, n.release_status, n.release_country, " \
          "n.label, n.catalog_number, n.barcode, n.disc_total, n.total_tracks, n.compilation"
    run "albums: existing rows updated in place", <<~SQL
      update albums a set (#{cols.join(', ')}, updated_at) = (#{src}, now())
      from album_map m join need_album n on n.akey = m.akey
      where a.id = m.album_id
    SQL
    run "albums: new albums inserted", <<~SQL
      with src as (
        select gen_random_uuid() as id, n.* from need_album n
        where not exists (select 1 from album_map m where m.akey = n.akey)),
      ins as (
        insert into albums (id, #{cols.join(', ')}, created_at, updated_at)
        select n.id, #{src}, now(), now() from src n
        returning id)
      insert into album_map select src.akey, src.id from src join ins on ins.id = src.id
    SQL
  end

  def update_songs
    run "songs: updated from tags", <<~SQL
      update songs s set
        title = coalesce(k.title_name, s.title),
        track_number = case when t.track_number > 0 then t.track_number else s.track_number end,
        disc_number = case when t.disc_number > 0 then t.disc_number else s.disc_number end,
        artist_credit = k.artist_name,
        artist_id = k.artist_id,
        album_id = coalesce(am.album_id, s.album_id),
        genre_id = coalesce(gm.genre_id, s.genre_id),
        musicbrainz_recording_id = coalesce(lrec.gid, t.musicbrainz_recording_id),
        musicbrainz_release_track_id = t.musicbrainz_release_track_id,
        updated_at = now()
      from sk k
      join song_file_tags t on t.song_id = k.song_id
      join song_genre sg on sg.song_id = k.song_id
      left join genre_map gm on gm.key = pg_temp.genre_key(sg.name)
      left join album_map am on am.akey = k.akey
      left join lk_recording lrec on lrec.tag_gid = t.musicbrainz_recording_id
      where s.id = k.song_id
    SQL
  end

  # Every credited artist per song, in credit order. The main artist is position 0.
  def rebuild_credits
    conn.execute("delete from song_artist_credits")
    run "credits: inserted", <<~SQL
      insert into song_artist_credits (song_id, artist_id, position, created_at, updated_at)
      select song_id, artist_id, min(pos), now(), now() from (
        select t.song_id, a.id as artist_id, (u.ord - 1)::int as pos
        from song_file_tags t
        join sk on sk.song_id = t.song_id
        cross join lateral unnest(t.musicbrainz_artist_ids) with ordinality as u(gid, ord)
        join lk_artist l on l.tag_gid = u.gid
        join artists a on a.musicbrainz_id = l.gid
        union all
        select sk.song_id, sk.artist_id, 0 from sk where sk.artist_id is not null) x
      group by song_id, artist_id
    SQL
  end

  def cleanup
    run "albums: deleted (no songs left)", <<~SQL
      delete from albums a where not exists (select 1 from songs s where s.album_id = a.id)
    SQL
    run "artists: deleted (no songs, albums or credits left)", <<~SQL
      delete from artists a
      where not exists (select 1 from songs s where s.artist_id = a.id)
        and not exists (select 1 from albums b where b.artist_id = a.id)
        and not exists (select 1 from song_artist_credits c where c.artist_id = a.id)
    SQL
    run "genres: deleted (no songs left)", <<~SQL
      delete from genres g where not exists (select 1 from songs s where s.genre_id = g.id)
    SQL
    run "genres: renamed to the most common tag spelling", <<~SQL
      update genres g set name = n.name, updated_at = now()
      from genre_map m join need_genre n on n.key = m.key
      where g.id = m.genre_id and g.name <> n.name
        and not exists (select 1 from genres o where o.name = n.name and o.id <> g.id)
    SQL
  end

  def report
    say ""
    {
      "songs" => "select count(*) from songs",
      "  with artist" => "select count(*) from songs where artist_id is not null",
      "  with album" => "select count(*) from songs where album_id is not null",
      "  with genre" => "select count(*) from songs where genre_id is not null",
      "  with MusicBrainz recording id" => "select count(*) from songs where musicbrainz_recording_id is not null",
      "  with disc number" => "select count(*) from songs where disc_number is not null",
      "artists" => "select count(*) from artists",
      "  with MusicBrainz id" => "select count(*) from artists where musicbrainz_id is not null",
      "albums" => "select count(*) from albums",
      "  with MusicBrainz release id" => "select count(*) from albums where musicbrainz_release_id is not null",
      "  with album artist" => "select count(*) from albums where artist_id is not null",
      "  with year" => "select count(*) from albums where release_year is not null",
      "  compilations (various artists)" => "select count(*) from albums where compilation",
      "genres" => "select count(*) from genres",
      "song artist credits" => "select count(*) from song_artist_credits",
      "  songs with more than one credited artist" => "select count(*) from (select 1 from song_artist_credits group by song_id having count(*) > 1) x"
    }.each { |label, sql| say format("%-58s %8d", label, count(sql)) }
  end
end
