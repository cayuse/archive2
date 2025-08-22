class AudioFileProcessingJob < ApplicationJob
  queue_as :default

  def perform(song_id)
    song = Song.find_by(id: song_id)
    return unless song
    
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
      
      # Update song with extracted metadata (always use extracted metadata when available)
      updates = {}
      
      # Basic metadata - always use extracted metadata when available
      updates[:title] = metadata[:title] if metadata[:title].present?
      updates[:track_number] = metadata[:track_number] if metadata[:track_number].present?
      updates[:duration] = metadata[:duration] if metadata[:duration].present?
      updates[:file_format] = metadata[:file_format] if metadata[:file_format].present?
      updates[:file_size] = metadata[:file_size] if metadata[:file_size].present?
      
      # Handle artist - always use extracted metadata when available
      if metadata[:artist].present?
        artist = Artist.find_or_create_by(name: metadata[:artist])
        updates[:artist_id] = artist.id
      end
      
      # Handle album - always use extracted metadata when available
      if metadata[:album].present?
        album = Album.find_or_create_by(title: metadata[:album])
        updates[:album_id] = album.id
      end
      
      # Handle genre - always use extracted metadata when available
      if metadata[:genre].present?
        genre = Genre.find_or_create_by(name: metadata[:genre])
        updates[:genre_id] = genre.id
      end
      
      # Determine final status based on completeness criteria (title + artist)
      final_title = updates[:title] || song.title
      final_artist_id = updates[:artist_id] || song.artist_id
      
      if final_title.present? && final_artist_id.present?
        updates[:processing_status] = 'completed'
      else
        updates[:processing_status] = 'needs_review'
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