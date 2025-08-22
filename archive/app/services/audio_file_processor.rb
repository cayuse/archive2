require 'open3'

class AudioFileProcessor
  def initialize(file_path, content_type, file_size, original_filename: nil)
    @file_path = file_path
    @content_type = content_type
    @file_size = file_size
    # Prefer the original uploaded filename for parsing; fall back to temp file name
    @filename = (original_filename.presence || File.basename(file_path)).to_s
  end

  def process
    # Try to extract metadata using ffprobe first
    metadata = extract_metadata_with_ffprobe

    # If no metadata found, fall back to filename parsing
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

  def extract_metadata_with_ffprobe
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

    begin
      # Use the exact ffprobe command that works
      cmd = [
        'ffprobe', '-v', 'quiet',
        '-of', 'json',
        '-show_entries', 'format_tags',
        @file_path
      ]
      
      stdout, stderr, status = Open3.capture3(*cmd)
      
      if status.success?
        data = JSON.parse(stdout) rescue {}
        tags = (data.dig('format', 'tags') || {})
        
        # Extract metadata with case-insensitive fallbacks
        file_info[:title] = clean_string(tags['title'] || tags['TITLE'])
        file_info[:artist] = clean_string(tags['artist'] || tags['ARTIST'])
        file_info[:album] = clean_string(tags['album'] || tags['ALBUM'])
        file_info[:genre] = clean_string(tags['genre'] || tags['GENRE'])
        
        # Handle track number from various possible tag names
        track_tag = tags['track'] || tags['TRACK'] || tags['tracknumber'] || tags['TRACKNUMBER']
        if track_tag
          file_info[:track_number] = track_tag.to_s.split('/').first.to_i
        end
        
        # Get duration separately since we're not showing format info
        duration_cmd = [
          'ffprobe', '-v', 'quiet',
          '-of', 'json',
          '-show_entries', 'format=duration',
          @file_path
        ]
        
        duration_stdout, duration_stderr, duration_status = Open3.capture3(*duration_cmd)
        if duration_status.success?
          duration_data = JSON.parse(duration_stdout) rescue {}
          duration = duration_data.dig('format', 'duration')
          file_info[:duration] = duration.to_f.round if duration
        end
      end

      file_info
    rescue => e
      Rails.logger.warn "ffprobe metadata extraction error for #{@filename}: #{e.message}"
      file_info
    end
  end

  # WahWah support removed; ffprobe handles metadata

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
    # Remove file extension and normalize common separators/leading track numbers
    name = filename.gsub(/\.[^.]*$/, '')
    # Strip leading track numbers like "01 - ", "101-", "01_"
    name = name.sub(/^\d+\s*[-_.]\s*/, '')
    # Replace underscores with spaces for better parsing
    name = name.tr('_', ' ').strip
    
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
    cleaned = str
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