class CreateThemes < ActiveRecord::Migration[8.0]
  def change
    create_table :themes do |t|
      t.string :name, null: false
      t.string :display_name, null: false
      t.text :description
      t.string :primary_color
      t.string :secondary_color
      t.string :accent_color
      t.string :background_color
      t.string :surface_color
      t.string :text_color
      t.string :text_muted_color
      t.string :border_color
      t.string :success_color
      t.string :warning_color
      t.string :error_color
      t.string :info_color
      t.string :link_color
      t.string :link_hover_color
      t.string :button_primary_bg
      t.string :button_primary_text
      t.string :button_secondary_bg
      t.string :button_secondary_text
      t.string :card_bg
      t.string :card_border
      t.string :navbar_bg
      t.boolean :is_default, default: false
      t.boolean :is_active, default: false

      t.timestamps
    end

    add_index :themes, :name, unique: true
    add_index :themes, :is_default
    add_index :themes, :is_active
  end
end
