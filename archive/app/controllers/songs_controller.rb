class SongsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_song, only: [:show, :edit, :update, :destroy]
  before_action :authorize_song!, only: [:show, :edit, :update, :destroy]
  
  def index
    @songs = policy_scope(Song)
                  .includes(:artist, :album, :genre)
                  .order(created_at: :desc)
                  .limit(50) # Show first 50 songs, more will load via AJAX
  end
  
  def show
    # Show song details
  end
  
  def search
    query = params[:q]&.strip
    page = params[:page]&.to_i || 1
    per_page = 20
    
    @songs = policy_scope(Song)
                  .includes(:artist, :album, :genre)
                  .order(created_at: :desc)
    
    if query.present?
      # Use a more efficient search with proper joins
      @songs = @songs.joins("LEFT JOIN artists ON songs.artist_id = artists.id")
                     .joins("LEFT JOIN albums ON songs.album_id = albums.id")
                     .joins("LEFT JOIN genres ON songs.genre_id = genres.id")
                     .where("songs.title ILIKE ? OR artists.name ILIKE ? OR albums.title ILIKE ? OR genres.name ILIKE ?", 
                            "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
                     .distinct
    end
    
    @songs = @songs.offset((page - 1) * per_page).limit(per_page)
    
    respond_to do |format|
      format.html { render partial: 'songs/song_list', locals: { songs: @songs } }
      format.json { render json: { songs: @songs, has_more: @songs.count == per_page } }
    end
  end
  
  def new
    @song = Song.new
    authorize @song
  end
  
  def create
    @song = Song.new(song_params)
    authorize @song
    
    # Set initial processing status for new songs
    @song.processing_status = 'needs_review' if @song.processing_status.blank?
    
    # Store original filename if audio file is attached
    if @song.audio_file.attached?
      @song.original_filename = @song.audio_file.filename.to_s
    end
    
    if @song.save
      if Rails.env.development? && @song.audio_file.attached?
        Rails.logger.info "[Dev] Inline processing for song #{@song.id} via SongsController#create"
        AudioFileProcessingJob.perform_now(@song.id)
      end
      redirect_to edit_song_path(@song), notice: 'Song uploaded successfully. Please review the extracted metadata.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    # Only extract metadata if the song hasn't been processed before
    # Check for nil/blank processing_status (first time editing)
    if @song.processing_status.blank? && @song.audio_file.attached?
      Rails.logger.info "Extracting metadata for song #{@song.id} (#{@song.original_filename})"
      
      metadata = @song.extract_metadata_from_file
      
      Rails.logger.info "Metadata extraction result: #{metadata.inspect}"
      
      if metadata[:error].blank?
        # Pre-fill form with extracted metadata
        @extracted_metadata = metadata
        
        # Set basic metadata
        @song.title = metadata[:title] if metadata[:title].present?
        @song.track_number = metadata[:track_number] if metadata[:track_number].present?
        @song.duration = metadata[:duration] if metadata[:duration].present?
        @song.file_format = metadata[:file_format] if metadata[:file_format].present?
        @song.file_size = metadata[:file_size] if metadata[:file_size].present?
        
        # Handle artist
        if metadata[:artist].present?
          @song.artist = Artist.find_or_create_by(name: metadata[:artist])
          Rails.logger.info "Found/created artist: #{@song.artist.name}"
        end
        
        # Handle album
        if metadata[:album].present?
          @song.album = Album.find_or_create_by(title: metadata[:album])
          Rails.logger.info "Found/created album: #{@song.album.title}"
        elsif @song.album.nil?
          # Create a default album if none exists
          @song.album = Album.find_or_create_by(title: 'Unknown Album')
          Rails.logger.info "Created default album: Unknown Album"
        end
        
        # Handle genre
        if metadata[:genre].present?
          @song.genre = Genre.find_or_create_by(name: metadata[:genre])
          Rails.logger.info "Found/created genre: #{@song.genre.name}"
        elsif @song.genre.nil?
          @song.genre = Genre.find_or_create_by(name: 'Unknown Genre')
          Rails.logger.info "Created default genre: Unknown Genre"
        end
        
        # Determine processing status based on metadata completeness
        if @song.has_complete_metadata?
          @song.processing_status = 'completed'
          Rails.logger.info "Song has complete metadata - marked as completed"
        else
          @song.processing_status = 'needs_review'
          Rails.logger.info "Song has partial metadata - marked as needs_review"
        end
        
        # Use save instead of save! to handle validation errors gracefully
        if @song.save
          Rails.logger.info "Successfully saved song with extracted metadata"
          flash[:notice] = "Metadata extracted successfully. Please review and save."
        else
          Rails.logger.error "Failed to save extracted metadata: #{@song.errors.full_messages.join(', ')}"
          flash[:alert] = "Failed to save extracted metadata: #{@song.errors.full_messages.join(', ')}"
        end
      else
        Rails.logger.error "Metadata extraction failed: #{metadata[:error]}"
        @song.processing_status = 'failed'
        @song.processing_error = metadata[:error]
        
        if @song.save
          flash[:alert] = "Failed to extract metadata: #{metadata[:error]}"
        else
          flash[:alert] = "Failed to save song: #{@song.errors.full_messages.join(', ')}"
        end
      end
    elsif @song.processing_completed? && @song.audio_file.attached?
      # For completed songs, show the extracted metadata in the form
      Rails.logger.info "Showing extracted metadata for completed song #{@song.id}"
      
      # Create a metadata hash from the current song data for display
      @extracted_metadata = {
        title: @song.title,
        artist: @song.artist&.name,
        album: @song.album&.title,
        genre: @song.genre&.name,
        track_number: @song.track_number,
        duration: @song.duration,
        file_format: @song.file_format,
        file_size: @song.file_size
      }
    elsif @song.needs_review? && @song.audio_file.attached?
      # For songs that need review, show current metadata without re-extracting
      Rails.logger.info "Showing current metadata for song needing review #{@song.id}"
      
      # Create a metadata hash from the current song data for display
      @extracted_metadata = {
        title: @song.title,
        artist: @song.artist&.name,
        album: @song.album&.title,
        genre: @song.genre&.name,
        track_number: @song.track_number,
        duration: @song.duration,
        file_format: @song.file_format,
        file_size: @song.file_size
      }
    else
      Rails.logger.info "Skipping metadata extraction for song #{@song.id} (status: #{@song.processing_status}, has_audio: #{@song.audio_file.attached?})"
    end
  end
  
  def update
    # Check if this is a retry processing request
    if params[:retry_processing] == 'true' && @song.processing_failed?
      # Clear the error and reset status
      @song.processing_error = nil
      @song.processing_status = 'pending'
      
      if @song.save
        # Re-extract metadata from the file immediately
        Rails.logger.info "Retrying metadata extraction for song #{@song.id} (#{@song.original_filename})"
        
        metadata = @song.extract_metadata_from_file
        
        Rails.logger.info "Retry metadata extraction result: #{metadata.inspect}"
        
        if metadata[:error].blank?
          # Pre-fill form with extracted metadata
          @extracted_metadata = metadata
          
          # Set basic metadata
          @song.title = metadata[:title] if metadata[:title].present?
          @song.track_number = metadata[:track_number] if metadata[:track_number].present?
          @song.duration = metadata[:duration] if metadata[:duration].present?
          @song.file_format = metadata[:file_format] if metadata[:file_format].present?
          @song.file_size = metadata[:file_size] if metadata[:file_size].present?
          
          # Handle artist
          if metadata[:artist].present?
            @song.artist = Artist.find_or_create_by(name: metadata[:artist])
            Rails.logger.info "Found/created artist: #{@song.artist.name}"
          end
          
          # Handle album
          if metadata[:album].present?
            @song.album = Album.find_or_create_by(title: metadata[:album])
            Rails.logger.info "Found/created album: #{@song.album.title}"
          elsif @song.album.nil?
            # Create a default album if none exists
            @song.album = Album.find_or_create_by(title: 'Unknown Album')
            Rails.logger.info "Created default album: Unknown Album"
          end
          
          # Handle genre
          if metadata[:genre].present?
            @song.genre = Genre.find_or_create_by(name: metadata[:genre])
            Rails.logger.info "Found/created genre: #{@song.genre.name}"
          elsif @song.genre.nil?
            @song.genre = Genre.find_or_create_by(name: 'Unknown Genre')
            Rails.logger.info "Created default genre: Unknown Genre"
          end
          
          # Determine processing status based on metadata completeness
          if @song.has_complete_metadata?
            @song.processing_status = 'completed'
            Rails.logger.info "Song has complete metadata - marked as completed"
          else
            @song.processing_status = 'needs_review'
            Rails.logger.info "Song has partial metadata - marked as needs_review"
          end
          
          # Save the extracted metadata
          if @song.save
            Rails.logger.info "Successfully saved song with retry extracted metadata"
            redirect_to edit_song_path(@song), notice: 'Metadata re-extracted successfully. Please review and save.'
          else
            Rails.logger.error "Failed to save retry extracted metadata: #{@song.errors.full_messages.join(', ')}"
            redirect_to @song, alert: "Failed to save extracted metadata: #{@song.errors.full_messages.join(', ')}"
          end
        else
          Rails.logger.error "Retry metadata extraction failed: #{metadata[:error]}"
          @song.processing_status = 'failed'
          @song.processing_error = metadata[:error]
          
          if @song.save
            redirect_to @song, alert: "Failed to extract metadata: #{metadata[:error]}"
          else
            redirect_to @song, alert: "Failed to save song: #{@song.errors.full_messages.join(', ')}"
          end
        end
      else
        redirect_to @song, alert: 'Failed to restart processing.'
      end
      return
    end
    
    # Handle new artist/album/genre creation if names are provided but IDs are blank
    params = song_params.to_h
    
    # Extract the name fields before updating the song
    artist_name = params.delete(:artist_name)
    album_title = params.delete(:album_title)
    genre_name = params.delete(:genre_name)
    
    # Handle new artist
    if params[:artist_id].blank? && artist_name.present?
      artist = Artist.find_or_create_by(name: artist_name)
      params[:artist_id] = artist.id
    end
    
    # Handle new album
    if params[:album_id].blank? && album_title.present?
      album = Album.find_or_create_by(title: album_title)
      params[:album_id] = album.id
    end
    
    # Handle new genre
    if params[:genre_id].blank? && genre_name.present?
      genre = Genre.find_or_create_by(name: genre_name)
      params[:genre_id] = genre.id
    end
    
    if @song.update(params)
      redirect_to @song, notice: 'Song updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @song.destroy
    redirect_to songs_path, notice: 'Song deleted successfully.'
  end
  
  def maintenance
    authorize Song, :maintenance?
    
    @status_filter = params[:status] || 'needs_review'
    @songs = policy_scope(Song)
                  .includes(:artist, :album, :genre)
                  .order(created_at: :desc)
    
    # Apply status filter unless 'all' is selected
    if @status_filter != 'all'
      @songs = @songs.where(processing_status: @status_filter)
    end
    
    @songs = @songs.page(params[:page]).per(params[:per_page] || 20)
  end
  
  def bulk_update
    authorize Song, :bulk_update?
    
    song_ids = params[:song_ids] || []
    updates = params[:updates] || {}
    
    updated_count = 0
    errors = []
    
    song_ids.each do |id|
      song = Song.find_by(id: id)
      if song
        if song.update(updates)
          updated_count += 1
        else
          errors << "Song #{id}: #{song.errors.full_messages.join(', ')}"
        end
      else
        errors << "Song #{id} not found"
      end
    end
    
    if errors.any?
      flash[:alert] = "Updated #{updated_count} songs. Errors: #{errors.join('; ')}"
    else
      flash[:notice] = "Successfully updated #{updated_count} songs"
    end
    
    redirect_to maintenance_songs_path(status: params[:status_filter])
  end
  
  private
  
  def set_song
    @song = Song.includes(:artist, :album, :genre).find_by!(id: params[:id])
  end
  
  def authorize_song!
    authorize @song
  end
  
  def song_params
    params.require(:song).permit(:title, :track_number, :duration, :file_format, :file_size, 
                                :artist_id, :album_id, :genre_id, :processing_status, :processing_error,
                                :original_filename, :audio_file, :artist_name, :album_title, :genre_name)
  end
end 