class CreateSongAudioFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :song_audio_features, id: :uuid do |t|
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      t.string :analysis_model
      t.float :analyzed_seconds
      t.float :loudness_db
      t.float :peak_db
      t.float :tempo_bpm
      t.float :brightness_hz
      t.float :onset_strength
      t.float :energy
      t.float :danceability
      t.float :happiness
      t.float :aggression
      t.float :acousticness
      t.float :electronic
      t.float :instrumental
      t.float :speech
      t.datetime :analyzed_at

      t.timestamps
    end

    # the dials a stream is steered by
    add_index :song_audio_features, :energy
    add_index :song_audio_features, :speech
  end
end
