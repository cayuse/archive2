class JukeboxMonitorJob < ApplicationJob
  queue_as :default
  
  def perform
    jukebox_service = JukeboxService.new
    
    Rails.logger.info "Starting Jukebox Monitor Job"
    
    loop do
      begin
        # Handle requests from the Python player
        jukebox_service.handle_player_requests
        
        # Check system health periodically
        health = jukebox_service.get_system_health
        
        unless health[:healthy]
          Rails.logger.warn "Jukebox system health issues detected:"
          health[:recommendations].each do |rec|
            Rails.logger.warn "  - #{rec[:message]} (#{rec[:priority]} priority)"
          end
        end
        
        # Sleep for a bit before next check
        sleep(5)
        
      rescue => e
        Rails.logger.error "Error in Jukebox Monitor Job: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        sleep(10)  # Wait longer on error
      end
    end
  end
end 