namespace :intake do
  desc "Deal with drops as they arrive (the intake worker; runs until stopped)"
  task work: :environment do
    $stdout.sync = true
    running = true
    %w[INT TERM].each { |sig| trap(sig) { running = false } }
    # a release that adds the drop box starts this worker before its migration has been run
    until !running || IntakeBatch.table_exists?
      puts "intake worker waiting for the database migration"
      sleep 10
      IntakeBatch.reset_column_information
    end
    # One worker at a time: a deploy starts the new worker before the old one has gone, and two of them
    # must never share a batch. The lock belongs to this database session and is freed when the old
    # worker exits, however it exits.
    lock = ActiveRecord::Base.connection_pool.checkout
    puts "intake worker waiting for the previous worker to finish" unless lock.select_value("select pg_try_advisory_lock(#{Intake::WORKER_LOCK})")
    sleep 2 until !running || lock.select_value("select pg_try_advisory_lock(#{Intake::WORKER_LOCK})")
    next unless running
    # a batch left mid-way by a worker that was stopped is picked up again
    IntakeBatch.where(status: "processing").update_all(status: "queued")
    puts "intake worker watching #{Intake.root}"
    last_prune = nil
    while running
      if (batch = IntakeBatch.claim_next)
        puts "#{Time.current.iso8601} batch #{batch.id} (#{batch.name})"
        IntakeProcessor.new(batch).run
        puts "#{Time.current.iso8601}   #{batch.reload.counts.inspect}#{" ERROR #{batch.error}" if batch.error}"
      else
        if last_prune.nil? || last_prune < 1.hour.ago
          cleared = Intake.prune_originals
          puts "#{Time.current.iso8601} removed the kept originals of #{cleared} old drops" if cleared.positive?
          last_prune = Time.current
        end
        sleep 3
      end
    end
  end

  desc "Deal with every waiting drop, then stop"
  task run: :environment do
    while (batch = IntakeBatch.claim_next)
      IntakeProcessor.new(batch, log: Logger.new($stdout)).run
      puts "#{batch.name}: #{batch.reload.counts.inspect}#{" ERROR #{batch.error}" if batch.error}"
    end
  end

  desc "Drop a local file or folder into the drop box as a user: intake:drop[path,email]"
  task :drop, [ :path, :email ] => :environment do |_t, args|
    user = User.find_by!(email: args[:email])
    root = Pathname.new(args[:path]).expand_path
    batch = IntakeBatch.create!(user: user, name: root.basename.to_s)
    files = root.file? ? [ root ] : Dir.glob(root.join("**/*").to_s).select { |f| File.file?(f) }.map { |f| Pathname.new(f) }
    files.each { |f| File.open(f, "rb") { |io| batch.receive!(io, root.file? ? f.basename.to_s : File.join(root.basename.to_s, f.relative_path_from(root).to_s)) } }
    batch.finish_upload!
    puts "queued #{files.size} files as batch #{batch.id}"
  end
end
