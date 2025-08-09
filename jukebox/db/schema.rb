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

ActiveRecord::Schema[8.0].define(version: 2025_07_21_000205) do
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

  create_table "jukebox_cached_songs", force: :cascade do |t|
    t.bigint "song_id", null: false
    t.string "file_path", null: false
    t.bigint "file_size", null: false
    t.string "status", default: "downloading"
    t.datetime "downloaded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["file_path"], name: "index_jukebox_cached_songs_on_file_path"
    t.index ["song_id"], name: "index_jukebox_cached_songs_on_song_id", unique: true
    t.index ["status"], name: "index_jukebox_cached_songs_on_status"
  end

  create_table "jukebox_playlist_songs", force: :cascade do |t|
    t.bigint "jukebox_playlist_id", null: false
    t.bigint "song_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jukebox_playlist_id", "position"], name: "idx_on_jukebox_playlist_id_position_a388ebf6a3"
    t.index ["jukebox_playlist_id", "song_id"], name: "idx_on_jukebox_playlist_id_song_id_0a93278e5c", unique: true
    t.index ["jukebox_playlist_id"], name: "index_jukebox_playlist_songs_on_jukebox_playlist_id"
    t.index ["song_id"], name: "index_jukebox_playlist_songs_on_song_id"
  end

  create_table "jukebox_playlists", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "archive_playlist_id", null: false
    t.boolean "active", default: true
    t.boolean "jukebox_enabled", default: false
    t.integer "crossfade_duration", default: 0
    t.integer "volume", default: 80
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_public", default: true, null: false
    t.index ["active"], name: "index_jukebox_playlists_on_active"
    t.index ["archive_playlist_id"], name: "index_jukebox_playlists_on_archive_playlist_id", unique: true
    t.index ["is_public"], name: "index_jukebox_playlists_on_is_public"
    t.index ["jukebox_enabled"], name: "index_jukebox_playlists_on_jukebox_enabled"
  end

  create_table "jukebox_queue_items", force: :cascade do |t|
    t.bigint "song_id", null: false
    t.bigint "user_id"
    t.integer "position", null: false
    t.string "status", default: "pending"
    t.datetime "played_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_jukebox_queue_items_on_position"
    t.index ["song_id"], name: "index_jukebox_queue_items_on_song_id"
    t.index ["status", "position"], name: "index_jukebox_queue_items_on_status_and_position"
    t.index ["status"], name: "index_jukebox_queue_items_on_status"
    t.index ["user_id"], name: "index_jukebox_queue_items_on_user_id"
  end

  create_table "songs", force: :cascade do |t|
    t.string "title"
    t.string "artist"
    t.string "album"
    t.string "genre"
    t.integer "year"
    t.integer "duration"
    t.string "file_path"
    t.integer "file_size"
    t.integer "bitrate"
    t.integer "sample_rate"
    t.integer "channels"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "system_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "theme_assets", force: :cascade do |t|
    t.integer "theme_id", null: false
    t.string "asset_type", null: false
    t.string "filename", null: false
    t.string "display_name", null: false
    t.text "description"
    t.string "url"
    t.integer "size"
    t.string "mime_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["theme_id", "asset_type", "filename"], name: "index_theme_assets_on_theme_id_and_asset_type_and_filename", unique: true
    t.index ["theme_id"], name: "index_theme_assets_on_theme_id"
  end

  create_table "themes", force: :cascade do |t|
    t.string "name", null: false
    t.string "display_name", null: false
    t.text "description"
    t.string "primary_color"
    t.string "secondary_color"
    t.string "accent_color"
    t.string "background_color"
    t.string "surface_color"
    t.string "text_color"
    t.string "text_muted_color"
    t.string "border_color"
    t.string "success_color"
    t.string "warning_color"
    t.string "error_color"
    t.string "info_color"
    t.string "link_color"
    t.string "link_hover_color"
    t.string "button_primary_bg"
    t.string "button_primary_text"
    t.string "button_secondary_bg"
    t.string "button_secondary_text"
    t.string "card_bg"
    t.string "card_border"
    t.string "navbar_bg"
    t.boolean "is_default", default: false
    t.boolean "is_active", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_themes_on_is_active"
    t.index ["is_default"], name: "index_themes_on_is_default"
    t.index ["name"], name: "index_themes_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.string "password_confirmation"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "jukebox_cached_songs", "songs", on_delete: :cascade
  add_foreign_key "jukebox_playlist_songs", "jukebox_playlists", on_delete: :cascade
  add_foreign_key "jukebox_queue_items", "users", on_delete: :nullify
  add_foreign_key "theme_assets", "themes"
end
