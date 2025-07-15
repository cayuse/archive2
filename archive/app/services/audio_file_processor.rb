class AudioFileProcessor
  def initialize(file_path, content_type, file_size)
    @file_path = file_path
    @content_type = content_type
    @file_size = file_size
    @filename = File.basename(file_path)
  end

  def process
    # Try to extract metadata from ID3 tags first
    metadata = extract_metadata_from_tags
    
    # If no metadata found in tags, fall back to filename parsing
    if metadata[:title].blank? && metadata[:artist].blank?
      filename_metadata = extract_metadata_from_filename
      metadata.merge!(filename_metadata)
    end
    
    metadata
  rescue => e
    Rails.logger.error "AudioFileProcessor failed: #{e.message}"
    { error: e.message }
  end

  private

  def extract_metadata_from_tags
    require 'wahwah'
    
    # Basic file information
    file_info = {
      file_format: extract_file_format,
      file_size: @file_size,
      title: nil,
      artist: nil,
      album: nil,
      genre: nil,
      track_number: nil,
      duration: nil
    }
    
    # Only try to read tags for supported formats
    return file_info unless supported_format_for_tags?
    
    Rails.logger.info "Attempting to extract metadata from #{@filename} (format: #{extract_file_format})"
    
    begin
      tag = WahWah.open(@file_path)
      
      # Log what we're trying to extract
      Rails.logger.info "WahWah tag object: #{tag.inspect}"
      Rails.logger.info "Available methods: #{tag.methods.grep(/title|artist|album|genre|track|duration/)}"
      
      # For m4a files, WahWah might have limited support
      if extract_file_format == 'm4a'
        Rails.logger.info "Processing M4A file - WahWah support may be limited"
      end
      
      file_info[:title] = tag.title unless tag.title.nil? || tag.title.to_s.strip == ''
      file_info[:artist] = tag.artist unless tag.artist.nil? || tag.artist.to_s.strip == ''
      file_info[:album] = tag.album unless tag.album.nil? || tag.album.to_s.strip == ''
      file_info[:genre] = tag.genre unless tag.genre.nil? || tag.genre.to_s.strip == ''
      file_info[:track_number] = tag.track.to_i if tag.track
      file_info[:duration] = tag.duration.to_i if tag.duration
      
      # Log extracted values
      Rails.logger.info "Extracted metadata: #{file_info.inspect}"
      
      # Clean up any empty strings
      file_info.each do |key, value|
        file_info[key] = nil if value.is_a?(String) && value.strip == ''
      end
      
      # For m4a files, if we didn't get any metadata, try alternative approach
      if extract_file_format == 'm4a' && file_info[:title].blank? && file_info[:artist].blank?
        Rails.logger.info "M4A file has no metadata - will fall back to filename parsing"
      end
    rescue => e
      # Log error in production
      Rails.logger.warn "Failed to read ID3 tags from #{@filename}: #{e.message}"
      Rails.logger.warn "Error backtrace: #{e.backtrace.first(5).join("\n")}"
      
      # For m4a files, this might be expected due to WahWah limitations
      if extract_file_format == 'm4a'
        Rails.logger.info "M4A metadata extraction failed - this may be normal for WahWah"
      end
    end
    
    file_info
  end

  def supported_format_for_tags?
    # WahWah supports MP3, FLAC, OGG, M4A, WAV
    # Note: M4A support might be limited in WahWah
    supported = %w[mp3 flac ogg m4a wav].include?(extract_file_format)
    Rails.logger.info "Format #{extract_file_format} supported for tags: #{supported}"
    supported
  end

  def extract_metadata_from_filename
    # Extract basic file information
    file_info = {
      file_format: extract_file_format,
      file_size: @file_size,
      title: nil,
      artist: nil,
      album: nil,
      genre: nil,
      track_number: nil,
      duration: nil
    }

    # Try to extract metadata from filename
    filename_metadata = parse_filename(@filename)
    file_info.merge!(filename_metadata)

    # If we couldn't extract anything useful, that's okay - just return what we have
    # The job will handle this appropriately
    file_info

    file_info
  end

  def extract_file_format
    case @content_type
    when 'audio/mpeg', 'audio/mp3'
      'mp3'
    when 'audio/x-m4a', 'audio/mp4'
      'm4a'
    when 'audio/ogg'
      'ogg'
    when 'audio/flac'
      'flac'
    when 'audio/wav'
      'wav'
    when 'audio/aac'
      'aac'
    else
      # Fallback to file extension
      File.extname(@filename).downcase.gsub('.', '')
    end
  end

  def parse_filename(filename)
    # Remove file extension
    name = filename.gsub(/\.[^.]*$/, '')
    
    # Common filename patterns
    patterns = [
      # Artist - Album - Track - Title
      /^(.+?)\s*-\s*(.+?)\s*-\s*(\d+)\s*-\s*(.+)$/i,
      # Artist - Album - Title
      /^(.+?)\s*-\s*(.+?)\s*-\s*(.+)$/i,
      # Artist - Title
      /^(.+?)\s*-\s*(.+)$/i,
      # Just title
      /^(.+)$/i
    ]

    metadata = {}

    patterns.each do |pattern|
      if match = name.match(pattern)
        case pattern.source
        when /Artist.*Album.*Track.*Title/
          metadata[:artist] = clean_string(match[1])
          metadata[:album] = clean_string(match[2])
          metadata[:track_number] = match[3].to_i
          metadata[:title] = clean_string(match[4])
        when /Artist.*Album.*Title/
          metadata[:artist] = clean_string(match[1])
          metadata[:album] = clean_string(match[2])
          metadata[:title] = clean_string(match[3])
        when /Artist.*Title/
          metadata[:artist] = clean_string(match[1])
          metadata[:title] = clean_string(match[2])
        when /Just title/
          metadata[:title] = clean_string(match[1])
        end
        break
      end
    end

    metadata
  end

  def clean_string(str)
    return nil if str.blank?
    
    # Remove common separators and clean up
    cleaned = str.strip
      .gsub(/[_-]/, ' ')  # Replace underscores and dashes with spaces
      .gsub(/\s+/, ' ')   # Normalize whitespace
      .strip
    
    cleaned.presence
  end

  # Placeholder methods for when audio gems are available
  def extract_mp3_metadata
    # This would use taglib-ruby or ruby-mp3info when available
    {}
  end

  def extract_m4a_metadata
    # This would extract iTunes metadata when available
    {}
  end

  def extract_ogg_metadata
    # This would extract Vorbis comments when available
    {}
  end

  def extract_flac_metadata
    # This would extract FLAC metadata when available
    {}
  end
end 