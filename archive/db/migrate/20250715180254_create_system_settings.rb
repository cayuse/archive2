class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :system_settings, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :key
      t.text :value
      t.text :description

      t.timestamps
    end
  end
end
