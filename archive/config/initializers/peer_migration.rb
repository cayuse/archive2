# on_peers / once_on_peers in every migration (lib/peer_migration.rb, docs/PEERS.md).
require Rails.root.join("lib/peer_migration").to_s
ActiveSupport.on_load(:active_record) { ActiveRecord::Migration.include(PeerMigration) }
