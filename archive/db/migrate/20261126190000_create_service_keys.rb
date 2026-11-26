# Keys for programs (not people) that work on the archive through a narrow API. A key opens one
# scope and nothing else; only its SHA-256 digest is stored.
class CreateServiceKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :service_keys, id: :uuid do |t|
      t.string :name, null: false
      t.string :scope, null: false
      t.string :token_digest, null: false
      t.string :token_hint
      t.datetime :last_used_at
      t.string :last_used_ip
      t.bigint :writes_count, null: false, default: 0
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :service_keys, :token_digest, unique: true
    add_index :service_keys, :name, unique: true
  end
end
