class AddSongJob < ApplicationJob
  queue_as :default

  def perform(*args)
    Rails.logger.info "AddSongJob: Starting song refill"
    
    begin
      # Get the next song from the jukebox system
      next_song = get_next_song
      
      if next_song
        Rails.logger.info "AddSongJob: Adding song: #{next_song[:title]}"
        
        # Add to MPD queue
        result = mpd_client.play_song(next_song[:stream_url], false)
        
        if result[:success]
          Rails.logger.info "AddSongJob: Successfully added song to queue"
        else
          Rails.logger.error "AddSongJob: Failed to add song to queue: #{result[:error]}"
        end
      else
        Rails.logger.info "AddSongJob: No songs available for queue refill"
      end
      
    rescue => e
      Rails.logger.error "AddSongJob: Error during song refill: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  private

  def get_next_song
    # This would typically call your jukebox logic to get the next song
    # For now, we'll use a placeholder that can be customized
    
    begin
      # Try to get next song from Redis queue first
      redis = Redis.new(url: ENV['REDIS_URL'])
      queue_data = redis.lpop('jukebox:queue')
      
      if queue_data
        song_data = JSON.parse(queue_data)
        return song_data if song_data['stream_url']
      end
      
      # Fallback: try to get from random pool
      random_data = redis.lpop('jukebox:random_pool')
      
      if random_data
        song_data = JSON.parse(random_data)
        return song_data if song_data['stream_url']
      end
      
      # If no songs in queue or random pool, trigger a refill
      trigger_queue_refill
      
      nil
      
    rescue => e
      Rails.logger.error "AddSongJob: Error getting next song: #{e.message}"
      nil
    end
  end

  def trigger_queue_refill
    # This would trigger your jukebox logic to refill the queue
    # For now, we'll just log it
    Rails.logger.info "AddSongJob: Queue empty, triggering refill"
    
    # You could enqueue another job here or call your jukebox logic directly
    # RefillQueueJob.perform_later
  end

  def mpd_client
    @mpd_client ||= Rails.application.config.mpd_client
  end
end
