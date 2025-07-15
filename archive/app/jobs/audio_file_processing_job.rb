class AudioFileProcessingJob < ApplicationJob
  queue_as :default

  def perform(song_id)
    song = Song.find(song_id)
    
    # Skip if no audio file attached
    return unless song.audio_file.attached?
    
    # Skip if already processing or completed
    return if song.processing_in_progress? || song.processing_completed?
    
    # Update status to processing
    song.update(processing_status: 'processing', processing_error: nil)
    
    begin
      # Extract metadata from file
      metadata = song.extract_metadata_from_file
      Rails.logger.info "[AudioFileProcessingJob] Extracted metadata for song #{song.id}: #{metadata.inspect}"
      
      if metadata[:error].present?
        # Processing failed - but don't mark as failed if it's just "no metadata found"
        # This is a normal case that should be marked as "needs_review"
        if metadata[:error] == "No metadata found in filename"
          song.update(
            processing_status: 'needs_review',
            processing_error: nil
          )
        else
          song.update(
            processing_status: 'failed',
            processing_error: metadata[:error]
          )
        end
        return
      end
      
      # Update song with extracted metadata
      updates = {}
      
      # Basic metadata
      updates[:title] = metadata[:title] if metadata[:title].present?
      updates[:track_number] = metadata[:track_number] if metadata[:track_number].present?
      updates[:duration] = metadata[:duration] if metadata[:duration].present?
      updates[:file_format] = metadata[:file_format] if metadata[:file_format].present?
      updates[:file_size] = metadata[:file_size] if metadata[:file_size].present?
      
      # Handle artist and album
      if metadata[:artist].present?
        artist = Artist.find_or_create_by(name: metadata[:artist])
        updates[:artist_id] = artist.id
        
        if metadata[:album].present?
          album = Album.find_or_create_by(title: metadata[:album])
          updates[:album_id] = album.id
        elsif song.album.nil?
          # Create a default album if none exists
          album = Album.find_or_create_by(title: 'Unknown Album')
          updates[:album_id] = album.id
        end
      elsif song.artist.nil?
        # Create default artist if no metadata
        unknown_artist = Artist.find_or_create_by(name: 'Unknown Artist')
        updates[:artist_id] = unknown_artist.id
        
        if song.album.nil?
          # Create default album if none exists
          album = Album.find_or_create_by(title: 'Unknown Album')
          updates[:album_id] = album.id
        end
      end
      
      # Handle genre
      if metadata[:genre].present?
        genre = Genre.find_or_create_by(name: metadata[:genre])
        updates[:genre_id] = genre.id
      elsif song.genre.nil?
        # Create default genre if none exists
        genre = Genre.find_or_create_by(name: 'Unknown Genre')
        updates[:genre_id] = genre.id
      end
      
      # Determine final status based on metadata completeness
      if updates[:title].present? && updates[:artist_id].present? && updates[:album_id].present? && updates[:genre_id].present?
        updates[:processing_status] = 'completed'
      elsif updates[:title].present? || updates[:artist_id].present? || updates[:album_id].present? || updates[:genre_id].present?
        updates[:processing_status] = 'needs_review'
      else
        updates[:processing_status] = 'new'
      end
      
      Rails.logger.info "[AudioFileProcessingJob] Update hash for song #{song.id}: #{updates.inspect}"
      # Apply updates
      song.update(updates)
      
    rescue => e
      # Log error and mark as failed
      Rails.logger.error "AudioFileProcessingJob failed for song #{song_id}: #{e.message}"
      song.update(
        processing_status: 'failed',
        processing_error: e.message
      )
    end
  end
end 