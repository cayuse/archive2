class SongsController < ApplicationController
  def index
    @songs = Song.completed
                  .includes(:artist, :album, :genre, audio_file_attachment: :blob)
                  .recent
                  .page(params[:page])
                  .per(params[:per_page] || 20)
  end

  def show
    @song = Song.includes(:artist, :album, :genre).find_by!(id: params[:id])
  end

  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @songs = Song.completed
                  .includes(:artist, :album, :genre, audio_file_attachment: :blob)
                  .recent
    
    if query.present?
      @songs = @songs.search(query)
    end
    
    @songs = @songs.page(page).per(per_page)
    
    respond_to do |format|
      format.html { render partial: 'songs/song_list', locals: { songs: @songs } }
      format.json { render json: { songs: @songs, has_more: @songs.count == per_page } }
    end
  end

  # Move a song to the top of the queue (position #1)
  def move_to_top
    order_number = params[:order_number].to_i
    
    # Find the queue item by order number
    queue_item = JukeboxQueueItem.find_by(position: order_number, status: ['0', '1', 'pending', 'pending_random'])
    
    if queue_item
      # Mark the song as a manual queue item (status '0') so it gets proper priority
      queue_item.update_column(:status, '0')
      
      # Get all pending queue items
      pending_items = JukeboxQueueItem.where(status: ['0', '1', 'pending', 'pending_random'])
                                      .where.not(id: queue_item.id)
                                      .order(:position)
      
      # Reorder: target song gets position 1, others get 2, 3, 4...
      queue_item.update_column(:position, 1)
      
      new_position = 2
      pending_items.each do |item|
        item.update_column(:position, new_position)
        new_position += 1
      end
      
      render json: { success: true, message: "Song moved to top of queue" }
    else
      render json: { success: false, message: "Queue item not found" }, status: :not_found
    end
  end

  # Remove a song from the queue by order number
  def remove_from_queue
    order_number = params[:order_number].to_i
    
    # Find the queue item by order number
    queue_item = JukeboxQueueItem.find_by(position: order_number, status: ['0', '1', 'pending', 'pending_random'])
    
    if queue_item
      # Delete the queue item
      queue_item.destroy
      
      # Reorder remaining items to fill the gap
      remaining_items = JukeboxQueueItem.where(status: ['0', '1', 'pending', 'pending_random'])
                                        .where('position > ?', order_number)
                                        .order(:position)
      
      remaining_items.each do |item|
        item.update_column(:position, item.position - 1)
      end
      
      render json: { success: true, message: "Song removed from queue" }
    else
      render json: { success: false, message: "Queue item not found" }, status: :not_found
    end
  end

  # Add a song to the queue (regular controller action, not API)
  def add_to_queue
    @song = Song.find(params[:id])
    
    begin
      jukebox_service = JukeboxService.instance
      queue_item = jukebox_service.add_to_queue(@song.id)
      
      flash[:notice] = "\"#{@song.title}\" by #{@song.artist&.name || 'Unknown Artist'} added to queue"
      redirect_to live_path
    rescue ActiveRecord::RecordNotFound
      flash[:alert] = 'Song not found'
      redirect_back(fallback_location: songs_path)
    rescue => e
      flash[:alert] = "Failed to add song to queue: #{e.message}"
      redirect_back(fallback_location: songs_path)
    end
  end
end 