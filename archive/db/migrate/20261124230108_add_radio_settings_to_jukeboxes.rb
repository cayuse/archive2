class AddRadioSettingsToJukeboxes < ActiveRecord::Migration[8.0]
  def change
    # radio auto-fill settings: { "genre" => "any|adjacent|strict", "steer" => { "energy" => 0.6, ... } }
    add_column :jukeboxes, :radio_settings, :jsonb, null: false, default: {}
  end
end
