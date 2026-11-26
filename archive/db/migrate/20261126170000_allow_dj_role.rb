# users.role gained "dj" (3) in the model, but the database check still allowed only 0..2, so
# saving a DJ failed.
class AllowDjRole < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE users DROP CONSTRAINT check_valid_role"
    execute "ALTER TABLE users ADD CONSTRAINT check_valid_role CHECK (role = ANY (ARRAY[0, 1, 2, 3]))"
  end

  def down
    execute "ALTER TABLE users DROP CONSTRAINT check_valid_role"
    execute "ALTER TABLE users ADD CONSTRAINT check_valid_role CHECK (role = ANY (ARRAY[0, 1, 2]))"
  end
end
