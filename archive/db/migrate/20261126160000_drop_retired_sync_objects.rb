# The standalone jukeboxes and the master/slave sync that fed them are gone (see git tag
# pre-jukebox-removal). This removes what they left in the database: the change log and key
# tables, the old star ratings (replaced by station thumbs) and the logical-replication publication.
# Nothing in the app reads any of it. Production was dumped before this ran; see KAMAL_DEPLOY.md.
class DropRetiredSyncObjects < ActiveRecord::Migration[8.1]
  TABLES = %i[sync_changes conflict_logs slave_keys jukebox_keys song_ratings].freeze

  def up
    execute "DROP PUBLICATION IF EXISTS pub_archive"
    TABLES.each { |table| drop_table table, if_exists: true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "restore these tables from a backup taken before this migration"
  end
end
