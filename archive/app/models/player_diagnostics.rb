# What browser players report about themselves (AudioEngine#getDiagnostics: buffering, stalls,
# blocked starts, the next song loading ahead), kept in log/player_diagnostics.log. The app's own
# log goes to the container's output and is lost on every deploy; this file sits on the log volume
# (config/deploy.yml) and survives, so a week of a locked iPhone's track changes can be read back:
#
#   kamal app exec --reuse 'grep "event=track_end\|event=advance_done\|event=stall" log/player_diagnostics.log'
#
# Rotates at 10 MB, keeping 5 files.
module PlayerDiagnostics
  PATH = Rails.root.join("log", "player_diagnostics.log")

  def self.log(line)
    logger.info("#{Time.current.utc.iso8601(3)} #{line}")
  rescue StandardError => e
    Rails.logger.warn("[AJB diag] could not write #{PATH}: #{e.message}")
  end

  def self.logger
    @logger ||= Logger.new(PATH, 5, 10.megabytes).tap { |l| l.formatter = ->(_sev, _time, _prog, msg) { "#{msg}\n" } }
  end
end
