namespace :analysis do
  desc "Issue a key for the sound-analysis API: analysis:key[name]. The key is printed once."
  task :key, [ :name ] => :environment do |_t, args|
    abort "give the key a name: rake \"analysis:key[my-pc]\"" if args[:name].blank?
    _key, token = ServiceKey.issue!(name: args[:name], scope: "analysis")
    puts token
  end

  desc "List analysis keys (never the keys themselves)"
  task keys: :environment do
    ServiceKey.order(:created_at).each do |k|
      puts format("%-20s …%-4s  %-8s created %s  last used %s from %s  %d writes", k.name, k.token_hint, k.revoked_at ? "REVOKED" : "active",
                  k.created_at.to_date, k.last_used_at&.iso8601 || "never", k.last_used_ip || "-", k.writes_count)
    end
  end

  desc "Revoke an analysis key: analysis:revoke[name]"
  task :revoke, [ :name ] => :environment do |_t, args|
    ServiceKey.find_by!(name: args[:name]).revoke!
    puts "revoked #{args[:name]}"
  end
end
