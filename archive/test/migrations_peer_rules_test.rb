require "test_helper"

# Once peers are mirrored, a migration that changes a SHARED table must do it through on_peers
# (schema) or once_on_peers (data): see PeerMigration and docs/PEERS.md, "Continued development".
# This checks every migration written after peers were introduced. A deliberate exception carries a
# comment saying why:  # peers: <reason>
class MigrationsPeerRulesTest < ActiveSupport::TestCase
  BASELINE = 20261126190000   # the last migration before peers
  SCHEMA = /\b(add_column|remove_column|rename_column|change_column\w*|add_index|remove_index|add_reference|remove_reference|
               add_foreign_key|remove_foreign_key|add_timestamps|remove_timestamps|create_table|drop_table|rename_table|
               change_table|create_join_table|add_check_constraint|remove_check_constraint)\b/x
  DATA = /\b(update_all|delete_all|destroy_all|insert_all|upsert_all|create!?|find_each|update!?|save!?)\b|\bexecute\b/
  RENAME = /\b(rename_column|rename_table)\b/

  def migrations_after_baseline
    Dir[Rails.root.join("db/migrate/*.rb")].select { |f| File.basename(f).to_i > BASELINE }
  end

  def shared_tables_named(source)
    PeerSync::SHARED_TABLES.select { |t| source.match?(/[:"']#{t}\b/) }
  end

  test "new migrations change shared tables only through on_peers / once_on_peers" do
    problems = migrations_after_baseline.filter_map do |file|
      source = File.read(file)
      next if source.match?(/#\s*peers:/)
      shared = shared_tables_named(source)
      next if shared.empty?
      issues = []
      issues << "schema change to #{shared.join(', ')} outside on_peers" if source.match?(SCHEMA) && !source.include?("on_peers")
      issues << "data change outside once_on_peers" if source.match?(DATA) && !source.include?("once_on_peers")
      issues << "renames a shared table or column: old code on the other peers still uses the old name during a release (add, copy, then drop instead)" if source.match?(RENAME)
      "#{File.basename(file)}: #{issues.join('; ')}" if issues.any?
    end
    assert_empty problems, "See docs/PEERS.md, \"Continued development\":\n#{problems.join("\n")}"
  end
end
