class UploadController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_upload!

  def show
    @song = Song.new
  end

  def create
    @song = Song.new(song_params)
    authorize @song
    
    # Set initial processing status
    @song.processing_status = 'needs_review'
    
    # Set the user
    @song.user = current_user
    
    # Store original filename if audio file is attached
    if @song.audio_file.attached?
      @song.original_filename = @song.audio_file.filename.to_s
      Rails.logger.info "Uploading file: #{@song.original_filename} (#{@song.audio_file.content_type})"
    end
    
    # Set a temporary title from the filename if not provided
    if @song.title.blank? && params[:song][:audio_file].present?
      @song.title = params[:song][:audio_file].original_filename.chomp(File.extname(params[:song][:audio_file].original_filename))
    end
    
    Rails.logger.info "About to save song with params: #{song_params.inspect}"
    Rails.logger.info "Song valid? #{@song.valid?}"
    Rails.logger.info "Song errors: #{@song.errors.full_messages}" unless @song.valid?
    
    if @song.save
      Rails.logger.info "Song saved with ID: #{@song.id}, processing_status: #{@song.processing_status}"

      # In development, process metadata immediately in-app
      if Rails.env.development? && @song.audio_file.attached?
        Rails.logger.info "[Dev] Inline processing for song #{@song.id}"
        AudioFileProcessingJob.perform_now(@song.id)
      end

      redirect_to edit_song_path(@song), notice: 'File uploaded successfully. Please review the extracted metadata.'
    else
      Rails.logger.error "Failed to save song: #{@song.errors.full_messages.join(', ')}"
      render :show, status: :unprocessable_entity
    end
  end

  private

  def authorize_upload!
    authorize Song, :upload?
  end

  def song_params
    permitted_params = params.require(:song).permit(:title, :track_number, :duration, :file_format, :file_size, 
                                                   :album_id, :genre_id, :processing_status, :processing_error,
                                                   :original_filename, :audio_file, :user_id)
    
    # Convert empty strings to nil for optional associations
    permitted_params[:album_id] = nil if permitted_params[:album_id].blank?
    permitted_params[:genre_id] = nil if permitted_params[:genre_id].blank?
    
    permitted_params
  end
end 