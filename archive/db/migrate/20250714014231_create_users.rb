class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.integer :role, default: 0, null: false
      t.string :password_digest, null: false

      t.timestamps
    end
    
    # Add indexes for performance and data integrity
    add_index :users, :email, unique: true
    add_index :users, :role
    
    # Add a check constraint to ensure valid role values
    add_check_constraint :users, "role IN (0, 1, 2)", name: "check_valid_role"
  end
end
