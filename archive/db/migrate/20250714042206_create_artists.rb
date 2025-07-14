class CreateArtists < ActiveRecord::Migration[8.0]
  def change
    create_table :artists do |t|
      t.string :name, null: false
      t.text :biography
      t.string :country
      t.integer :formed_year
      t.string :website
      t.string :image_url

      t.timestamps
    end
    
    # Add indexes for performance and data integrity
    add_index :artists, :name, unique: true
    add_index :artists, :country
    add_index :artists, :formed_year
    
    # Add check constraint for reasonable formed year
    add_check_constraint :artists, "formed_year IS NULL OR (formed_year >= 1900 AND formed_year <= 2030)", name: "check_reasonable_formed_year"
  end
end
