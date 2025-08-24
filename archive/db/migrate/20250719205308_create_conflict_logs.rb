class CreateConflictLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :conflict_logs, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :conflict_type, null: false
      t.jsonb :master_change
      t.jsonb :slave_change
      t.string :resolution, null: false
      t.text :reason
      t.timestamp :resolved_at, null: false

      t.timestamps
    end

    add_index :conflict_logs, :conflict_type
    add_index :conflict_logs, :resolved_at
  end
end
