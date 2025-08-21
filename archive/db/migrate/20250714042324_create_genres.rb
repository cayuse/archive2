class CreateGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :genres, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :name, null: false
      t.text :description
      t.string :color

      t.timestamps
    end
    
    # Add indexes for performance and data integrity
    add_index :genres, :name, unique: true
    
    # Add check constraint for valid hex color format
    add_check_constraint :genres, "color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$'", name: "check_valid_hex_color"
  end
end
