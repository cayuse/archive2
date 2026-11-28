# Library quality: every song's file measured and fingerprinted, copies of one recording merged onto
# the best one without deleting anything, and the reasons recorded.
#
#   song_measurements  one per song: the audit's verdict and numbers for its stored file, and its
#                      Chromaprint fingerprint (raw, plus sampled values with a GIN index for finding
#                      copies of the same recording)
#   songs.canonical_song_id  set on a copy that is hidden because another copy of the same recording
#                      plays instead; nil means the song is live
#   song_issues        why a song is what it is: broken, flawed, low fidelity, superseded, duplicate;
#                      several per song, each open until resolved
#   song_merges        each hide, with every row it moved (playlists, queues, votes), so a restore
#                      puts everything back exactly
#   intake_watch_files files the intake worker has seen in its watched folders, so each is taken once
#   intake_batches.source   "upload" (the Drop Box page) or "watch:<name>" (a watched folder)
#   intake_items.outcome    what the merge made of an imported file: new / better / not_better
class CreateLibraryQuality < ActiveRecord::Migration[8.1]
  def change
    create_table :song_measurements, id: :uuid do |t|
      t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :blob_checksum
      t.integer :measure_version, null: false
      t.integer :score_version, null: false
      t.string :verdict, null: false
      t.integer :quality
      t.string :codec
      t.integer :kbps
      t.boolean :lossless, null: false, default: false
      t.integer :bits
      t.integer :sample_rate
      t.float :eff_khz
      t.float :duration
      t.float :loudness_lufs
      t.jsonb :problems, null: false, default: []
      t.jsonb :notes, null: false, default: []
      t.jsonb :data
      t.binary :fingerprint
      t.integer :fingerprint_keys, array: true
      t.text :acoustid_fingerprint
      t.datetime :measured_at, null: false
      t.timestamps
    end
    add_index :song_measurements, :fingerprint_keys, using: :gin
    add_index :song_measurements, :verdict

    add_reference :songs, :canonical_song, type: :uuid, foreign_key: { to_table: :songs, on_delete: :nullify }, index: true

    create_table :song_issues, id: :uuid do |t|
      t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :source, null: false
      t.references :related_song, type: :uuid, foreign_key: { to_table: :songs, on_delete: :nullify }
      t.jsonb :detail, null: false, default: {}
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :song_issues, [ :kind, :resolved_at ]

    create_table :song_merges, id: :uuid do |t|
      t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :canonical_song, type: :uuid, null: false, foreign_key: { to_table: :songs, on_delete: :cascade }
      t.string :reason, null: false
      t.string :source, null: false
      t.jsonb :moves, null: false, default: []
      t.datetime :reverted_at
      t.timestamps
    end

    create_table :intake_watch_files, id: :uuid do |t|
      t.string :watch, null: false
      t.text :path, null: false
      t.bigint :byte_size, null: false
      t.datetime :file_mtime, null: false
      t.references :intake_batch, type: :uuid, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :intake_watch_files, [ :watch, :path ], unique: true

    add_column :intake_batches, :source, :string, null: false, default: "upload"
    add_column :intake_items, :outcome, :string
  end
end
