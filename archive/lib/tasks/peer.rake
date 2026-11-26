# Peer sync (docs/PEERS.md). Arguments come from the environment, because DSNs contain commas and
# spaces that rake's [a,b] syntax cannot carry. Run inside the app container:
#   kamal app exec --reuse 'bin/rails peer:status'
namespace :peer do
  desc "Show this node, its subscriptions, who reads from it, and dangling references"
  task status: :environment do
    puts "node:          #{PeerSync.node_name || '(not a peer: pglogical not set up)'}"
    puts "archive node:  #{SystemSetting.archive_node_id}"
    PeerSync.subscriptions.each do |s|
      still = PeerSync.syncing_tables(s["subscription_name"])
      puts "receives from: #{s['provider_node']} (#{s['subscription_name']}): #{s['status']}#{still.any? ? ", still copying #{still.size} tables" : ''}"
    end
    PeerSync.outgoing.each { |o| puts "read by:       #{o['slot_name']}  active=#{o['active']}  behind=#{o['behind']}  wal=#{o['wal_status']}" } if PeerSync.installed?
    bad = PeerSync.unclassified_tables
    puts "UNCLASSIFIED TABLES (add to PeerSync): #{bad.join(', ')}" if bad.any?
    d = PeerSync.dangling
    puts d.any? ? "dangling references: #{d.inspect}" : "dangling references: none"
  end

  desc "How many of the library's files are on this peer's disk (files follow the database)"
  task files: :environment do
    present, total, missing = PeerSync.file_presence
    puts "#{present} of #{total} files present#{missing.any? ? "; missing e.g. #{missing.join(', ')}" : ''}"
  end

  desc "Make this database a peer node: PEER_NAME=bigballs PEER_DSN='host=... port=... dbname=... user=... password=...'"
  task setup_node: :environment do
    added = PeerSync.setup_node!(name: ENV.fetch("PEER_NAME"), dsn: ENV.fetch("PEER_DSN"))
    puts "node #{PeerSync.node_name}; tables added to #{PeerSync::SET}: #{added.empty? ? 'none (all there)' : added.join(', ')}"
  end

  desc "Receive from another peer: SUBSCRIPTION=from_bigballs PROVIDER_DSN='...' COPY=1 (copy only into an empty peer)"
  task subscribe: :environment do
    PeerSync.subscribe!(name: ENV.fetch("SUBSCRIPTION"), provider_dsn: ENV.fetch("PROVIDER_DSN"), copy: ENV["COPY"] == "1")
    puts "subscribed #{ENV['SUBSCRIPTION']}"
  end

  desc "Wait until a subscription has copied every table: SUBSCRIPTION=from_bigballs"
  task wait: :environment do
    name = ENV.fetch("SUBSCRIPTION")
    loop do
      status = PeerSync.subscriptions.find { |s| s["subscription_name"] == name }&.dig("status")
      left = PeerSync.syncing_tables(name)
      puts "#{Time.current.strftime('%H:%M:%S')} #{status}, #{left.size} tables still copying#{left.any? ? ": #{left.first(5).join(', ')}" : ''}"
      break if status == "replicating" && left.empty?
      abort "subscription #{name} is #{status}" if status == "down"
      sleep 5
    end
  end

  desc "Stop receiving from a peer: SUBSCRIPTION=from_bigballs"
  task unsubscribe: :environment do
    PeerSync.unsubscribe!(ENV.fetch("SUBSCRIPTION"))
    puts "dropped #{ENV['SUBSCRIPTION']}"
  end
end
