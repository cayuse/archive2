SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: update_albums_search_vector(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_albums_search_vector() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.search_vector := 
          setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
        RETURN NEW;
      END;
      $$;


--
-- Name: update_artists_search_vector(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_artists_search_vector() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.search_vector := 
          setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.biography, '')), 'B');
        RETURN NEW;
      END;
      $$;


--
-- Name: update_genres_search_vector(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_genres_search_vector() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.search_vector := 
          setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
        RETURN NEW;
      END;
      $$;


--
-- Name: update_songs_search_vector(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_songs_search_vector() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        NEW.search_vector := setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A');
        RETURN NEW;
      END;
      $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: ajb_played_songs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ajb_played_songs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    jukebox_id uuid NOT NULL,
    song_id uuid NOT NULL,
    played_at timestamp without time zone NOT NULL,
    source character varying DEFAULT 'random'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT check_valid_source CHECK (((source)::text = ANY (ARRAY[('random'::character varying)::text, ('requested'::character varying)::text])))
);


--
-- Name: ajb_queue_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ajb_queue_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    jukebox_id uuid NOT NULL,
    song_id uuid NOT NULL,
    "position" integer NOT NULL,
    source character varying DEFAULT 'random'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT check_positive_position CHECK (("position" > 0)),
    CONSTRAINT check_valid_source CHECK (((source)::text = ANY (ARRAY[('random'::character varying)::text, ('requested'::character varying)::text])))
);


--
-- Name: albums; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.albums (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying NOT NULL,
    release_date date,
    description text,
    cover_image_url character varying,
    total_tracks integer,
    duration integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    search_vector tsvector,
    artist_id uuid,
    musicbrainz_release_id uuid,
    musicbrainz_release_group_id uuid,
    artist_credit character varying,
    sort_title character varying,
    release_year integer,
    original_release_year integer,
    release_type character varying,
    secondary_types character varying,
    release_status character varying,
    release_country character varying,
    label character varying,
    catalog_number character varying,
    barcode character varying,
    disc_total integer,
    compilation boolean DEFAULT false NOT NULL,
    CONSTRAINT check_positive_duration CHECK (((duration IS NULL) OR (duration > 0))),
    CONSTRAINT check_positive_total_tracks CHECK (((total_tracks IS NULL) OR (total_tracks > 0))),
    CONSTRAINT check_reasonable_release_date CHECK (((release_date IS NULL) OR (release_date >= '1900-01-01'::date)))
);


--
-- Name: albums_genres; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.albums_genres (
    album_id uuid NOT NULL,
    genre_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: archive_nodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archive_nodes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    node_id character varying NOT NULL,
    name character varying NOT NULL,
    local_playback boolean DEFAULT false NOT NULL,
    player_url character varying,
    lan_cidr character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    player_token character varying,
    player_commands jsonb DEFAULT '[]'::jsonb NOT NULL,
    player_command_seq integer DEFAULT 0 NOT NULL,
    player_state jsonb DEFAULT '{}'::jsonb NOT NULL,
    player_seen_at timestamp(6) without time zone
);


--
-- Name: artists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    biography text,
    country character varying,
    formed_year integer,
    website character varying,
    image_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    search_vector tsvector,
    musicbrainz_id uuid,
    sort_name character varying,
    disambiguation character varying,
    artist_type character varying,
    CONSTRAINT check_reasonable_formed_year CHECK (((formed_year IS NULL) OR ((formed_year >= 1900) AND (formed_year <= 2030))))
);


--
-- Name: artists_genres; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.artists_genres (
    artist_id uuid NOT NULL,
    genre_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: genre_affinities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.genre_affinities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    genre_id uuid NOT NULL,
    related_genre_id uuid NOT NULL,
    score double precision NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: genres; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.genres (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    description text,
    color character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    search_vector tsvector,
    CONSTRAINT check_valid_hex_color CHECK (((color IS NULL) OR ((color)::text ~ '^#[0-9A-Fa-f]{6}$'::text)))
);


--
-- Name: jukebox_playlist_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jukebox_playlist_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    jukebox_id uuid NOT NULL,
    playlist_id uuid NOT NULL,
    weight integer DEFAULT 1 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jukeboxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jukeboxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    session_id character varying NOT NULL,
    owner_id uuid NOT NULL,
    private boolean DEFAULT false NOT NULL,
    status character varying DEFAULT 'inactive'::character varying NOT NULL,
    started_at timestamp without time zone,
    ended_at timestamp without time zone,
    scheduled_start timestamp without time zone,
    scheduled_end timestamp without time zone,
    crossfade_enabled boolean DEFAULT true NOT NULL,
    crossfade_duration integer DEFAULT 3000 NOT NULL,
    auto_play boolean DEFAULT true NOT NULL,
    description text,
    location character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    current_song_id uuid,
    current_position numeric(10,3) DEFAULT 0.0,
    is_playing boolean DEFAULT false,
    volume numeric(3,2) DEFAULT 0.8,
    last_status_update timestamp(6) without time zone,
    min_queue_length integer DEFAULT 5 NOT NULL,
    queue_refill_level integer DEFAULT 10 NOT NULL,
    guest_password character varying,
    fill_mode character varying DEFAULT 'random'::character varying NOT NULL,
    radio_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    admin_password character varying,
    server_playback boolean DEFAULT false NOT NULL,
    server_transport character varying DEFAULT 'stop'::character varying NOT NULL,
    station_id uuid,
    CONSTRAINT check_positive_min_queue_length CHECK ((min_queue_length > 0)),
    CONSTRAINT check_positive_queue_refill_level CHECK ((queue_refill_level > 0))
);


--
-- Name: playback_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playback_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    archive_node_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    user_id uuid NOT NULL,
    description text,
    is_public boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: playlists_songs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.playlists_songs (
    playlist_id uuid NOT NULL,
    song_id uuid NOT NULL,
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT check_positive_position CHECK ((("position" IS NULL) OR ("position" > 0)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: song_artist_credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.song_artist_credits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    song_id uuid NOT NULL,
    artist_id uuid NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: song_audio_features; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.song_audio_features (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    song_id uuid NOT NULL,
    analysis_model character varying,
    analyzed_seconds double precision,
    loudness_db double precision,
    peak_db double precision,
    tempo_bpm double precision,
    brightness_hz double precision,
    onset_strength double precision,
    energy double precision,
    danceability double precision,
    happiness double precision,
    aggression double precision,
    acousticness double precision,
    electronic double precision,
    instrumental double precision,
    speech double precision,
    analyzed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: song_embeddings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.song_embeddings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    song_id uuid NOT NULL,
    analysis_model character varying,
    dimensions integer,
    embedding real[] DEFAULT '{}'::real[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: song_file_tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.song_file_tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    song_id uuid NOT NULL,
    blob_key character varying,
    blob_checksum character varying,
    container character varying,
    codec character varying,
    tag_format character varying,
    bitrate integer,
    bitrate_mode character varying,
    sample_rate integer,
    channels integer,
    bits_per_sample integer,
    duration_seconds double precision,
    title character varying,
    artist character varying,
    album character varying,
    album_artist character varying,
    composer character varying,
    genre character varying,
    track_number integer,
    track_total integer,
    disc_number integer,
    disc_total integer,
    date_raw character varying,
    original_date_raw character varying,
    year integer,
    compilation boolean,
    artist_sort character varying,
    album_artist_sort character varying,
    album_sort character varying,
    label character varying,
    catalog_number character varying,
    barcode character varying,
    isrc character varying,
    asin character varying,
    media character varying,
    release_type character varying,
    release_status character varying,
    release_country character varying,
    language character varying,
    script character varying,
    bpm double precision,
    musicbrainz_recording_id uuid,
    musicbrainz_release_id uuid,
    musicbrainz_release_group_id uuid,
    musicbrainz_release_track_id uuid,
    musicbrainz_work_id uuid,
    musicbrainz_artist_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    musicbrainz_album_artist_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    acoustid_id uuid,
    acoustid_fingerprint text,
    has_cover_art boolean DEFAULT false NOT NULL,
    has_lyrics boolean DEFAULT false NOT NULL,
    raw_tags jsonb DEFAULT '{}'::jsonb NOT NULL,
    scan_error text,
    scanned_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: song_neighbors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.song_neighbors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    song_id uuid NOT NULL,
    neighbor_id uuid NOT NULL,
    rank integer NOT NULL,
    score double precision NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: songs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.songs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying NOT NULL,
    album_id uuid,
    track_number integer,
    duration integer,
    file_format character varying,
    file_size bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    genre_id uuid,
    search_vector tsvector,
    processing_status character varying,
    processing_error text,
    artist_id uuid,
    original_filename character varying,
    user_id uuid,
    disc_number integer,
    artist_credit character varying,
    musicbrainz_recording_id uuid,
    musicbrainz_release_track_id uuid,
    CONSTRAINT check_positive_duration CHECK (((duration IS NULL) OR (duration > 0))),
    CONSTRAINT check_positive_file_size CHECK (((file_size IS NULL) OR (file_size > 0))),
    CONSTRAINT check_positive_track_number CHECK (((track_number IS NULL) OR (track_number > 0)))
);


--
-- Name: station_feedbacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_feedbacks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    jukebox_id uuid,
    song_id uuid NOT NULL,
    kind character varying NOT NULL,
    "position" double precision,
    expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    station_id uuid
);


--
-- Name: station_playlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.station_playlists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    station_id uuid NOT NULL,
    playlist_id uuid NOT NULL,
    mode character varying DEFAULT 'inspire'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: stations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name character varying NOT NULL,
    name_edited boolean DEFAULT false NOT NULL,
    permanent boolean DEFAULT false NOT NULL,
    implicit boolean DEFAULT false NOT NULL,
    shared boolean DEFAULT false NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    origin_archive character varying,
    parent_id uuid,
    forked_at timestamp(6) without time zone,
    archived_at timestamp(6) without time zone,
    recipe_digest character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying,
    value text,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: theme_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.theme_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    theme_id uuid NOT NULL,
    asset_type character varying NOT NULL,
    filename character varying NOT NULL,
    display_name character varying NOT NULL,
    description text,
    file_data bytea NOT NULL,
    content_type character varying NOT NULL,
    checksum character varying NOT NULL,
    file_size integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: theme_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.theme_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    value text NOT NULL,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: themes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.themes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    display_name character varying NOT NULL,
    description text,
    version character varying DEFAULT '1.0.0'::character varying,
    is_active boolean DEFAULT true,
    is_default boolean DEFAULT false,
    primary_bg character varying DEFAULT '#0f0f23'::character varying,
    secondary_bg character varying DEFAULT '#1a1a2e'::character varying,
    accent_color character varying DEFAULT '#4f46e5'::character varying,
    accent_hover character varying DEFAULT '#6366f1'::character varying,
    accent_active character varying DEFAULT '#3730a3'::character varying,
    text_primary character varying DEFAULT '#f8fafc'::character varying,
    text_secondary character varying DEFAULT '#cbd5e1'::character varying,
    text_muted character varying DEFAULT '#64748b'::character varying,
    text_inverse character varying DEFAULT '#ffffff'::character varying,
    border_color character varying DEFAULT '#334155'::character varying,
    shadow_color character varying DEFAULT 'rgba(0, 0, 0, 0.1)'::character varying,
    overlay_color character varying DEFAULT 'rgba(0, 0, 0, 0.5)'::character varying,
    success_color character varying DEFAULT '#10b981'::character varying,
    warning_color character varying DEFAULT '#f59e0b'::character varying,
    danger_color character varying DEFAULT '#ef4444'::character varying,
    button_bg character varying DEFAULT '#374151'::character varying,
    button_hover character varying DEFAULT '#4b5563'::character varying,
    button_active character varying DEFAULT '#1f2937'::character varying,
    highlight_color character varying DEFAULT '#3b82f6'::character varying,
    link_color character varying DEFAULT '#60a5fa'::character varying,
    link_hover character varying DEFAULT '#93c5fd'::character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    css_variables jsonb DEFAULT '{}'::jsonb,
    custom_css text,
    heading_color character varying,
    card_header_text character varying
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT check_valid_role CHECK ((role = ANY (ARRAY[0, 1, 2, 3])))
);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ajb_played_songs ajb_played_songs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ajb_played_songs
    ADD CONSTRAINT ajb_played_songs_pkey PRIMARY KEY (id);


--
-- Name: ajb_queue_items ajb_queue_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ajb_queue_items
    ADD CONSTRAINT ajb_queue_items_pkey PRIMARY KEY (id);


--
-- Name: albums_genres albums_genres_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.albums_genres
    ADD CONSTRAINT albums_genres_pkey PRIMARY KEY (album_id, genre_id);


--
-- Name: albums albums_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.albums
    ADD CONSTRAINT albums_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: archive_nodes archive_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archive_nodes
    ADD CONSTRAINT archive_nodes_pkey PRIMARY KEY (id);


--
-- Name: artists_genres artists_genres_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artists_genres
    ADD CONSTRAINT artists_genres_pkey PRIMARY KEY (artist_id, genre_id);


--
-- Name: artists artists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artists
    ADD CONSTRAINT artists_pkey PRIMARY KEY (id);


--
-- Name: genre_affinities genre_affinities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genre_affinities
    ADD CONSTRAINT genre_affinities_pkey PRIMARY KEY (id);


--
-- Name: genres genres_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genres
    ADD CONSTRAINT genres_pkey PRIMARY KEY (id);


--
-- Name: jukebox_playlist_assignments jukebox_playlist_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jukebox_playlist_assignments
    ADD CONSTRAINT jukebox_playlist_assignments_pkey PRIMARY KEY (id);


--
-- Name: jukeboxes jukeboxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jukeboxes
    ADD CONSTRAINT jukeboxes_pkey PRIMARY KEY (id);


--
-- Name: playback_grants playback_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playback_grants
    ADD CONSTRAINT playback_grants_pkey PRIMARY KEY (id);


--
-- Name: playlists playlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT playlists_pkey PRIMARY KEY (id);


--
-- Name: playlists_songs playlists_songs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists_songs
    ADD CONSTRAINT playlists_songs_pkey PRIMARY KEY (playlist_id, song_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: song_artist_credits song_artist_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_artist_credits
    ADD CONSTRAINT song_artist_credits_pkey PRIMARY KEY (id);


--
-- Name: song_audio_features song_audio_features_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_audio_features
    ADD CONSTRAINT song_audio_features_pkey PRIMARY KEY (id);


--
-- Name: song_embeddings song_embeddings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_embeddings
    ADD CONSTRAINT song_embeddings_pkey PRIMARY KEY (id);


--
-- Name: song_file_tags song_file_tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_file_tags
    ADD CONSTRAINT song_file_tags_pkey PRIMARY KEY (id);


--
-- Name: song_neighbors song_neighbors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_neighbors
    ADD CONSTRAINT song_neighbors_pkey PRIMARY KEY (id);


--
-- Name: songs songs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songs
    ADD CONSTRAINT songs_pkey PRIMARY KEY (id);


--
-- Name: station_feedbacks station_feedbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_feedbacks
    ADD CONSTRAINT station_feedbacks_pkey PRIMARY KEY (id);


--
-- Name: station_playlists station_playlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_playlists
    ADD CONSTRAINT station_playlists_pkey PRIMARY KEY (id);


--
-- Name: stations stations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT stations_pkey PRIMARY KEY (id);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (id);


--
-- Name: theme_assets theme_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theme_assets
    ADD CONSTRAINT theme_assets_pkey PRIMARY KEY (id);


--
-- Name: theme_settings theme_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theme_settings
    ADD CONSTRAINT theme_settings_pkey PRIMARY KEY (id);


--
-- Name: themes themes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.themes
    ADD CONSTRAINT themes_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_jpa_jukebox_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jpa_jukebox_enabled ON public.jukebox_playlist_assignments USING btree (jukebox_id, enabled);


--
-- Name: idx_jpa_jukebox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jpa_jukebox_id ON public.jukebox_playlist_assignments USING btree (jukebox_id);


--
-- Name: idx_jpa_playlist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_jpa_playlist_id ON public.jukebox_playlist_assignments USING btree (playlist_id);


--
-- Name: idx_jpa_unique_assignment; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_jpa_unique_assignment ON public.jukebox_playlist_assignments USING btree (jukebox_id, playlist_id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_ajb_played_songs_on_jukebox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_played_songs_on_jukebox_id ON public.ajb_played_songs USING btree (jukebox_id);


--
-- Name: index_ajb_played_songs_on_jukebox_id_and_played_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_played_songs_on_jukebox_id_and_played_at ON public.ajb_played_songs USING btree (jukebox_id, played_at);


--
-- Name: index_ajb_played_songs_on_played_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_played_songs_on_played_at ON public.ajb_played_songs USING btree (played_at);


--
-- Name: index_ajb_played_songs_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_played_songs_on_song_id ON public.ajb_played_songs USING btree (song_id);


--
-- Name: index_ajb_queue_items_on_jukebox_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_queue_items_on_jukebox_id ON public.ajb_queue_items USING btree (jukebox_id);


--
-- Name: index_ajb_queue_items_on_jukebox_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_queue_items_on_jukebox_id_and_position ON public.ajb_queue_items USING btree (jukebox_id, "position");


--
-- Name: index_ajb_queue_items_on_jukebox_id_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_queue_items_on_jukebox_id_and_source ON public.ajb_queue_items USING btree (jukebox_id, source);


--
-- Name: index_ajb_queue_items_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ajb_queue_items_on_song_id ON public.ajb_queue_items USING btree (song_id);


--
-- Name: index_albums_genres_on_album_id_and_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_albums_genres_on_album_id_and_genre_id ON public.albums_genres USING btree (album_id, genre_id);


--
-- Name: index_albums_on_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_artist_id ON public.albums USING btree (artist_id);


--
-- Name: index_albums_on_musicbrainz_release_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_musicbrainz_release_group_id ON public.albums USING btree (musicbrainz_release_group_id);


--
-- Name: index_albums_on_musicbrainz_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_albums_on_musicbrainz_release_id ON public.albums USING btree (musicbrainz_release_id);


--
-- Name: index_albums_on_release_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_release_date ON public.albums USING btree (release_date);


--
-- Name: index_albums_on_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_search_vector ON public.albums USING gin (search_vector);


--
-- Name: index_albums_on_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_title ON public.albums USING btree (title);


--
-- Name: index_albums_on_title_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_title_gin ON public.albums USING gin (title public.gin_trgm_ops);


--
-- Name: index_albums_on_total_tracks; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_albums_on_total_tracks ON public.albums USING btree (total_tracks);


--
-- Name: index_archive_nodes_on_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_archive_nodes_on_node_id ON public.archive_nodes USING btree (node_id);


--
-- Name: index_archive_nodes_on_player_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_archive_nodes_on_player_token ON public.archive_nodes USING btree (player_token);


--
-- Name: index_artists_genres_on_artist_id_and_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_artists_genres_on_artist_id_and_genre_id ON public.artists_genres USING btree (artist_id, genre_id);


--
-- Name: index_artists_on_country; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_country ON public.artists USING btree (country);


--
-- Name: index_artists_on_formed_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_formed_year ON public.artists USING btree (formed_year);


--
-- Name: index_artists_on_musicbrainz_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_artists_on_musicbrainz_id ON public.artists USING btree (musicbrainz_id);


--
-- Name: index_artists_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_name ON public.artists USING btree (name);


--
-- Name: index_artists_on_name_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_name_gin ON public.artists USING gin (name public.gin_trgm_ops);


--
-- Name: index_artists_on_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_artists_on_search_vector ON public.artists USING gin (search_vector);


--
-- Name: index_genre_affinities_on_genre_id_and_related_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_genre_affinities_on_genre_id_and_related_genre_id ON public.genre_affinities USING btree (genre_id, related_genre_id);


--
-- Name: index_genre_affinities_on_related_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_genre_affinities_on_related_genre_id ON public.genre_affinities USING btree (related_genre_id);


--
-- Name: index_genres_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_genres_on_name ON public.genres USING btree (name);


--
-- Name: index_genres_on_name_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_genres_on_name_gin ON public.genres USING gin (name public.gin_trgm_ops);


--
-- Name: index_genres_on_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_genres_on_search_vector ON public.genres USING gin (search_vector);


--
-- Name: index_jukeboxes_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_created_at ON public.jukeboxes USING btree (created_at);


--
-- Name: index_jukeboxes_on_current_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_current_song_id ON public.jukeboxes USING btree (current_song_id);


--
-- Name: index_jukeboxes_on_guest_password; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_guest_password ON public.jukeboxes USING btree (guest_password);


--
-- Name: index_jukeboxes_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_owner_id ON public.jukeboxes USING btree (owner_id);


--
-- Name: index_jukeboxes_on_private; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_private ON public.jukeboxes USING btree (private);


--
-- Name: index_jukeboxes_on_private_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_private_and_status ON public.jukeboxes USING btree (private, status) WHERE (private = false);


--
-- Name: index_jukeboxes_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_jukeboxes_on_session_id ON public.jukeboxes USING btree (session_id);


--
-- Name: index_jukeboxes_on_station_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_station_id ON public.jukeboxes USING btree (station_id);


--
-- Name: index_jukeboxes_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jukeboxes_on_status ON public.jukeboxes USING btree (status);


--
-- Name: index_playback_grants_on_archive_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playback_grants_on_archive_node_id ON public.playback_grants USING btree (archive_node_id);


--
-- Name: index_playback_grants_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playback_grants_on_user_id ON public.playback_grants USING btree (user_id);


--
-- Name: index_playback_grants_on_user_id_and_archive_node_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_playback_grants_on_user_id_and_archive_node_id ON public.playback_grants USING btree (user_id, archive_node_id);


--
-- Name: index_playlists_on_is_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlists_on_is_public ON public.playlists USING btree (is_public);


--
-- Name: index_playlists_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlists_on_name ON public.playlists USING btree (name);


--
-- Name: index_playlists_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlists_on_user_id ON public.playlists USING btree (user_id);


--
-- Name: index_playlists_on_user_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_playlists_on_user_id_and_name ON public.playlists USING btree (user_id, name);


--
-- Name: index_playlists_songs_on_playlist_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_playlists_songs_on_playlist_id_and_position ON public.playlists_songs USING btree (playlist_id, "position");


--
-- Name: index_playlists_songs_on_playlist_id_and_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_playlists_songs_on_playlist_id_and_song_id ON public.playlists_songs USING btree (playlist_id, song_id);


--
-- Name: index_song_artist_credits_on_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_artist_credits_on_artist_id ON public.song_artist_credits USING btree (artist_id);


--
-- Name: index_song_artist_credits_on_song_id_and_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_song_artist_credits_on_song_id_and_artist_id ON public.song_artist_credits USING btree (song_id, artist_id);


--
-- Name: index_song_audio_features_on_energy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_audio_features_on_energy ON public.song_audio_features USING btree (energy);


--
-- Name: index_song_audio_features_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_song_audio_features_on_song_id ON public.song_audio_features USING btree (song_id);


--
-- Name: index_song_audio_features_on_speech; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_audio_features_on_speech ON public.song_audio_features USING btree (speech);


--
-- Name: index_song_embeddings_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_song_embeddings_on_song_id ON public.song_embeddings USING btree (song_id);


--
-- Name: index_song_file_tags_on_acoustid_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_acoustid_id ON public.song_file_tags USING btree (acoustid_id);


--
-- Name: index_song_file_tags_on_blob_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_blob_key ON public.song_file_tags USING btree (blob_key);


--
-- Name: index_song_file_tags_on_musicbrainz_album_artist_ids; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_musicbrainz_album_artist_ids ON public.song_file_tags USING gin (musicbrainz_album_artist_ids);


--
-- Name: index_song_file_tags_on_musicbrainz_artist_ids; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_musicbrainz_artist_ids ON public.song_file_tags USING gin (musicbrainz_artist_ids);


--
-- Name: index_song_file_tags_on_musicbrainz_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_musicbrainz_recording_id ON public.song_file_tags USING btree (musicbrainz_recording_id);


--
-- Name: index_song_file_tags_on_musicbrainz_release_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_musicbrainz_release_group_id ON public.song_file_tags USING btree (musicbrainz_release_group_id);


--
-- Name: index_song_file_tags_on_musicbrainz_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_file_tags_on_musicbrainz_release_id ON public.song_file_tags USING btree (musicbrainz_release_id);


--
-- Name: index_song_file_tags_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_song_file_tags_on_song_id ON public.song_file_tags USING btree (song_id);


--
-- Name: index_song_neighbors_on_neighbor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_song_neighbors_on_neighbor_id ON public.song_neighbors USING btree (neighbor_id);


--
-- Name: index_song_neighbors_on_song_id_and_rank; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_song_neighbors_on_song_id_and_rank ON public.song_neighbors USING btree (song_id, rank);


--
-- Name: index_songs_on_album_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_album_id ON public.songs USING btree (album_id);


--
-- Name: index_songs_on_album_id_and_track_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_album_id_and_track_number ON public.songs USING btree (album_id, track_number);


--
-- Name: index_songs_on_artist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_artist_id ON public.songs USING btree (artist_id);


--
-- Name: index_songs_on_created_at_desc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_created_at_desc ON public.songs USING btree (created_at);


--
-- Name: index_songs_on_file_format; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_file_format ON public.songs USING btree (file_format);


--
-- Name: index_songs_on_genre_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_genre_id ON public.songs USING btree (genre_id);


--
-- Name: index_songs_on_musicbrainz_recording_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_musicbrainz_recording_id ON public.songs USING btree (musicbrainz_recording_id);


--
-- Name: index_songs_on_musicbrainz_release_track_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_musicbrainz_release_track_id ON public.songs USING btree (musicbrainz_release_track_id);


--
-- Name: index_songs_on_processing_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_processing_status ON public.songs USING btree (processing_status);


--
-- Name: index_songs_on_search_vector; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_search_vector ON public.songs USING gin (search_vector);


--
-- Name: index_songs_on_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_status_and_created_at ON public.songs USING btree (processing_status, created_at);


--
-- Name: index_songs_on_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_title ON public.songs USING btree (title);


--
-- Name: index_songs_on_track_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_track_number ON public.songs USING btree (track_number);


--
-- Name: index_songs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_songs_on_user_id ON public.songs USING btree (user_id);


--
-- Name: index_station_feedbacks_on_jukebox_id_and_kind_and_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_station_feedbacks_on_jukebox_id_and_kind_and_song_id ON public.station_feedbacks USING btree (jukebox_id, kind, song_id);


--
-- Name: index_station_feedbacks_on_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_station_feedbacks_on_song_id ON public.station_feedbacks USING btree (song_id);


--
-- Name: index_station_feedbacks_on_station_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_station_feedbacks_on_station_id_and_created_at ON public.station_feedbacks USING btree (station_id, created_at);


--
-- Name: index_station_feedbacks_on_user_id_and_kind_and_song_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_station_feedbacks_on_user_id_and_kind_and_song_id ON public.station_feedbacks USING btree (user_id, kind, song_id);


--
-- Name: index_station_playlists_on_station_id_and_playlist_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_station_playlists_on_station_id_and_playlist_id ON public.station_playlists USING btree (station_id, playlist_id);


--
-- Name: index_stations_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stations_on_parent_id ON public.stations USING btree (parent_id);


--
-- Name: index_stations_on_recipe_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stations_on_recipe_digest ON public.stations USING btree (recipe_digest);


--
-- Name: index_stations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stations_on_user_id ON public.stations USING btree (user_id);


--
-- Name: index_theme_assets_on_theme_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_theme_assets_on_theme_id ON public.theme_assets USING btree (theme_id);


--
-- Name: index_theme_assets_on_theme_id_and_asset_type_and_filename; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_theme_assets_on_theme_id_and_asset_type_and_filename ON public.theme_assets USING btree (theme_id, asset_type, filename);


--
-- Name: index_theme_settings_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_theme_settings_on_key ON public.theme_settings USING btree (key);


--
-- Name: index_themes_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_themes_on_name ON public.themes USING btree (name);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_role ON public.users USING btree (role);


--
-- Name: albums albums_search_vector_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER albums_search_vector_update BEFORE INSERT OR UPDATE ON public.albums FOR EACH ROW EXECUTE FUNCTION public.update_albums_search_vector();


--
-- Name: artists artists_search_vector_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER artists_search_vector_update BEFORE INSERT OR UPDATE ON public.artists FOR EACH ROW EXECUTE FUNCTION public.update_artists_search_vector();


--
-- Name: genres genres_search_vector_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER genres_search_vector_update BEFORE INSERT OR UPDATE ON public.genres FOR EACH ROW EXECUTE FUNCTION public.update_genres_search_vector();


--
-- Name: songs songs_search_vector_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER songs_search_vector_update BEFORE INSERT OR UPDATE ON public.songs FOR EACH ROW EXECUTE FUNCTION public.update_songs_search_vector();


--
-- Name: ajb_played_songs fk_rails_00fe3365bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ajb_played_songs
    ADD CONSTRAINT fk_rails_00fe3365bc FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: albums fk_rails_124a79559a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.albums
    ADD CONSTRAINT fk_rails_124a79559a FOREIGN KEY (artist_id) REFERENCES public.artists(id);


--
-- Name: artists_genres fk_rails_163f472c49; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artists_genres
    ADD CONSTRAINT fk_rails_163f472c49 FOREIGN KEY (artist_id) REFERENCES public.artists(id) ON DELETE CASCADE;


--
-- Name: albums_genres fk_rails_174c2dd1ec; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.albums_genres
    ADD CONSTRAINT fk_rails_174c2dd1ec FOREIGN KEY (album_id) REFERENCES public.albums(id) ON DELETE CASCADE;


--
-- Name: jukebox_playlist_assignments fk_rails_258d82708a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jukebox_playlist_assignments
    ADD CONSTRAINT fk_rails_258d82708a FOREIGN KEY (jukebox_id) REFERENCES public.jukeboxes(id) ON DELETE CASCADE;


--
-- Name: station_feedbacks fk_rails_2878e0f5d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_feedbacks
    ADD CONSTRAINT fk_rails_2878e0f5d7 FOREIGN KEY (jukebox_id) REFERENCES public.jukeboxes(id) ON DELETE CASCADE;


--
-- Name: songs fk_rails_31272893df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songs
    ADD CONSTRAINT fk_rails_31272893df FOREIGN KEY (genre_id) REFERENCES public.genres(id);


--
-- Name: ajb_queue_items fk_rails_34fec7a969; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ajb_queue_items
    ADD CONSTRAINT fk_rails_34fec7a969 FOREIGN KEY (jukebox_id) REFERENCES public.jukeboxes(id) ON DELETE CASCADE;


--
-- Name: ajb_queue_items fk_rails_3c5a4b48fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ajb_queue_items
    ADD CONSTRAINT fk_rails_3c5a4b48fc FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: artists_genres fk_rails_44739bce00; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.artists_genres
    ADD CONSTRAINT fk_rails_44739bce00 FOREIGN KEY (genre_id) REFERENCES public.genres(id) ON DELETE CASCADE;


--
-- Name: playback_grants fk_rails_55f770ff1c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playback_grants
    ADD CONSTRAINT fk_rails_55f770ff1c FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ajb_played_songs fk_rails_56676bd3db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ajb_played_songs
    ADD CONSTRAINT fk_rails_56676bd3db FOREIGN KEY (jukebox_id) REFERENCES public.jukeboxes(id) ON DELETE CASCADE;


--
-- Name: jukebox_playlist_assignments fk_rails_58bced8741; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jukebox_playlist_assignments
    ADD CONSTRAINT fk_rails_58bced8741 FOREIGN KEY (playlist_id) REFERENCES public.playlists(id) ON DELETE CASCADE;


--
-- Name: songs fk_rails_5ce8fd4cc7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songs
    ADD CONSTRAINT fk_rails_5ce8fd4cc7 FOREIGN KEY (artist_id) REFERENCES public.artists(id);


--
-- Name: station_feedbacks fk_rails_648b45e4eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_feedbacks
    ADD CONSTRAINT fk_rails_648b45e4eb FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: song_embeddings fk_rails_6ca6134b9c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_embeddings
    ADD CONSTRAINT fk_rails_6ca6134b9c FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: song_file_tags fk_rails_6e2ac55a8a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_file_tags
    ADD CONSTRAINT fk_rails_6e2ac55a8a FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: song_neighbors fk_rails_7118a56581; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_neighbors
    ADD CONSTRAINT fk_rails_7118a56581 FOREIGN KEY (neighbor_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: station_feedbacks fk_rails_7b3c8fdc43; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_feedbacks
    ADD CONSTRAINT fk_rails_7b3c8fdc43 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: genre_affinities fk_rails_7e47348917; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genre_affinities
    ADD CONSTRAINT fk_rails_7e47348917 FOREIGN KEY (related_genre_id) REFERENCES public.genres(id) ON DELETE CASCADE;


--
-- Name: genre_affinities fk_rails_89cc7ddbba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.genre_affinities
    ADD CONSTRAINT fk_rails_89cc7ddbba FOREIGN KEY (genre_id) REFERENCES public.genres(id) ON DELETE CASCADE;


--
-- Name: stations fk_rails_991f66179f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stations
    ADD CONSTRAINT fk_rails_991f66179f FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: playlists_songs fk_rails_9e681bcd01; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists_songs
    ADD CONSTRAINT fk_rails_9e681bcd01 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: albums_genres fk_rails_9fe8ed8335; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.albums_genres
    ADD CONSTRAINT fk_rails_9fe8ed8335 FOREIGN KEY (genre_id) REFERENCES public.genres(id) ON DELETE CASCADE;


--
-- Name: playlists_songs fk_rails_b73231d400; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists_songs
    ADD CONSTRAINT fk_rails_b73231d400 FOREIGN KEY (playlist_id) REFERENCES public.playlists(id) ON DELETE CASCADE;


--
-- Name: station_playlists fk_rails_b8bdc02130; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_playlists
    ADD CONSTRAINT fk_rails_b8bdc02130 FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: playback_grants fk_rails_c112e16cb3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playback_grants
    ADD CONSTRAINT fk_rails_c112e16cb3 FOREIGN KEY (archive_node_id) REFERENCES public.archive_nodes(id) ON DELETE CASCADE;


--
-- Name: station_playlists fk_rails_c1efa06b23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_playlists
    ADD CONSTRAINT fk_rails_c1efa06b23 FOREIGN KEY (playlist_id) REFERENCES public.playlists(id) ON DELETE CASCADE;


--
-- Name: station_feedbacks fk_rails_c3364b53c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.station_feedbacks
    ADD CONSTRAINT fk_rails_c3364b53c4 FOREIGN KEY (station_id) REFERENCES public.stations(id) ON DELETE CASCADE;


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: song_artist_credits fk_rails_c852175111; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_artist_credits
    ADD CONSTRAINT fk_rails_c852175111 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: song_neighbors fk_rails_cb08cf50b6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_neighbors
    ADD CONSTRAINT fk_rails_cb08cf50b6 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: jukeboxes fk_rails_d180cd0a9b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jukeboxes
    ADD CONSTRAINT fk_rails_d180cd0a9b FOREIGN KEY (current_song_id) REFERENCES public.songs(id) ON DELETE SET NULL;


--
-- Name: songs fk_rails_d36a8dd57d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songs
    ADD CONSTRAINT fk_rails_d36a8dd57d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: playlists fk_rails_d67ef1eb45; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.playlists
    ADD CONSTRAINT fk_rails_d67ef1eb45 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: song_audio_features fk_rails_d8e6887ab5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_audio_features
    ADD CONSTRAINT fk_rails_d8e6887ab5 FOREIGN KEY (song_id) REFERENCES public.songs(id) ON DELETE CASCADE;


--
-- Name: theme_assets fk_rails_ddd35178ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.theme_assets
    ADD CONSTRAINT fk_rails_ddd35178ed FOREIGN KEY (theme_id) REFERENCES public.themes(id) ON DELETE CASCADE;


--
-- Name: song_artist_credits fk_rails_df9afe16f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.song_artist_credits
    ADD CONSTRAINT fk_rails_df9afe16f8 FOREIGN KEY (artist_id) REFERENCES public.artists(id) ON DELETE CASCADE;


--
-- Name: songs fk_rails_f4e40cd655; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.songs
    ADD CONSTRAINT fk_rails_f4e40cd655 FOREIGN KEY (album_id) REFERENCES public.albums(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261126170000'),
('20261126160000'),
('20261126150000'),
('20261126140000'),
('20261126130000'),
('20261126120100'),
('20261126120000'),
('20261126000000'),
('20261125190000'),
('20261124230108'),
('20261124223537'),
('20261124223519'),
('20261124211116'),
('20261124210021'),
('20261124205948'),
('20261124205919'),
('20261124194503'),
('20261124194457'),
('20261124194452'),
('20261124194446'),
('20261124161725'),
('20250810100000'),
('20250720235426'),
('20250719205308'),
('20250719202812'),
('20250719202803'),
('20250719202752'),
('20250719192041'),
('20250716001627'),
('20250715180254'),
('20250715162347'),
('20250715072009'),
('20250715053524'),
('20250715050755'),
('20250715040101'),
('20250715023850'),
('20250715000001'),
('20250714061901'),
('20250714044230'),
('20250714043221'),
('20250714043209'),
('20250714043159'),
('20250714043133'),
('20250714043109'),
('20250714043045'),
('20250714042324'),
('20250714042206'),
('20250714041822'),
('20250714014231'),
('20250128000003'),
('20250128000002'),
('20250128000001'),
('20250128000000'),
('20250127000002'),
('20250124000002'),
('20250124000001'),
('20250124000000'),
('20250121000000'),
('20250120000002'),
('20250120000001'),
('20250120000000');

