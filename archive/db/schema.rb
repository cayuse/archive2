# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_07_14_061901) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "albums", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "artist_id", null: false
    t.date "release_date"
    t.text "description"
    t.string "cover_image_url"
    t.integer "total_tracks"
    t.integer "duration"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.tsvector "search_vector"
    t.index ["artist_id"], name: "index_albums_on_artist_id"
    t.index ["release_date"], name: "index_albums_on_release_date"
    t.index ["search_vector"], name: "index_albums_on_search_vector", using: :gin
    t.index ["title"], name: "index_albums_on_title"
    t.index ["total_tracks"], name: "index_albums_on_total_tracks"
    t.check_constraint "duration IS NULL OR duration > 0", name: "check_positive_duration"
    t.check_constraint "release_date IS NULL OR release_date >= '1900-01-01'::date", name: "check_reasonable_release_date"
    t.check_constraint "total_tracks IS NULL OR total_tracks > 0", name: "check_positive_total_tracks"
  end

  create_table "albums_genres", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.bigint "genre_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["album_id", "genre_id"], name: "index_albums_genres_on_album_id_and_genre_id", unique: true
    t.index ["album_id"], name: "index_albums_genres_on_album_id"
    t.index ["genre_id"], name: "index_albums_genres_on_genre_id"
  end

  create_table "artists", force: :cascade do |t|
    t.string "name", null: false
    t.text "biography"
    t.string "country"
    t.integer "formed_year"
    t.string "website"
    t.string "image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.tsvector "search_vector"
    t.index ["country"], name: "index_artists_on_country"
    t.index ["formed_year"], name: "index_artists_on_formed_year"
    t.index ["name"], name: "index_artists_on_name", unique: true
    t.index ["search_vector"], name: "index_artists_on_search_vector", using: :gin
    t.check_constraint "formed_year IS NULL OR formed_year >= 1900 AND formed_year <= 2030", name: "check_reasonable_formed_year"
  end

  create_table "artists_genres", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.bigint "genre_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id", "genre_id"], name: "index_artists_genres_on_artist_id_and_genre_id", unique: true
    t.index ["artist_id"], name: "index_artists_genres_on_artist_id"
    t.index ["genre_id"], name: "index_artists_genres_on_genre_id"
  end

  create_table "genres", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.tsvector "search_vector"
    t.index ["name"], name: "index_genres_on_name", unique: true
    t.index ["search_vector"], name: "index_genres_on_search_vector", using: :gin
    t.check_constraint "color IS NULL OR color::text ~ '^#[0-9A-Fa-f]{6}$'::text", name: "check_valid_hex_color"
  end

  create_table "playlists", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "user_id", null: false
    t.text "description"
    t.boolean "is_public", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_public"], name: "index_playlists_on_is_public"
    t.index ["name"], name: "index_playlists_on_name"
    t.index ["user_id", "name"], name: "index_playlists_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_playlists_on_user_id"
  end

  create_table "playlists_songs", force: :cascade do |t|
    t.bigint "playlist_id", null: false
    t.bigint "song_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id", "position"], name: "index_playlists_songs_on_playlist_id_and_position"
    t.index ["playlist_id", "song_id"], name: "index_playlists_songs_on_playlist_id_and_song_id", unique: true
    t.index ["playlist_id"], name: "index_playlists_songs_on_playlist_id"
    t.index ["song_id"], name: "index_playlists_songs_on_song_id"
    t.check_constraint "\"position\" IS NULL OR \"position\" > 0", name: "check_positive_position"
  end

  create_table "songs", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "album_id", null: false
    t.integer "track_number"
    t.integer "duration"
    t.string "file_format"
    t.bigint "file_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "genre_id", null: false
    t.tsvector "search_vector"
    t.index ["album_id", "track_number"], name: "index_songs_on_album_id_and_track_number", unique: true
    t.index ["album_id"], name: "index_songs_on_album_id"
    t.index ["file_format"], name: "index_songs_on_file_format"
    t.index ["genre_id"], name: "index_songs_on_genre_id"
    t.index ["search_vector"], name: "index_songs_on_search_vector", using: :gin
    t.index ["title"], name: "index_songs_on_title"
    t.index ["track_number"], name: "index_songs_on_track_number"
    t.check_constraint "duration IS NULL OR duration > 0", name: "check_positive_duration"
    t.check_constraint "file_size IS NULL OR file_size > 0", name: "check_positive_file_size"
    t.check_constraint "track_number IS NULL OR track_number > 0", name: "check_positive_track_number"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.integer "role", default: 0, null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.check_constraint "role = ANY (ARRAY[0, 1, 2])", name: "check_valid_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "albums", "artists"
  add_foreign_key "albums_genres", "albums"
  add_foreign_key "albums_genres", "genres"
  add_foreign_key "artists_genres", "artists"
  add_foreign_key "artists_genres", "genres"
  add_foreign_key "playlists", "users"
  add_foreign_key "playlists_songs", "playlists"
  add_foreign_key "playlists_songs", "songs"
  add_foreign_key "songs", "albums"
  add_foreign_key "songs", "genres"
end
