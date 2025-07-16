#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'pathname'

# Windows-compatible standalone tag extractor
# Requirements: gem install wahwah

begin
  require 'wahwah'
rescue LoadError
  puts "Error: The 'wahwah' gem is not installed."
  puts "Please install it with: gem install wahwah"
  exit 1
end

class WindowsTagExtractor
  def initialize(verbose: false, output_format: :json)
    @verbose = verbose
    @output_format = output_format
  end

  def detect_file_type(file_path)
    # Read the first few bytes to detect file type
    File.open(file_path, 'rb') do |file|
      header = file.read(12)
      
      # MP3: ID3 or MPEG sync
      if header.start_with?('ID3') || header[0] == 0xFF && (header[1] & 0xE0) == 0xE0
        return '.mp3'
      end
      
      # M4A/MP4: ftyp box
      if header[4..7] == 'ftyp'
        return '.m4a'
      end
      
      # FLAC: fLaC signature
      if header.start_with?('fLaC')
        return '.flac'
      end
      
      # OGG: OggS signature
      if header.start_with?('OggS')
        return '.ogg'
      end
      
      # WAV: RIFF signature
      if header.start_with?('RIFF') && header[8..11] == 'WAVE'
        return '.wav'
      end
      
      # AAC: ADIF or ADTS
      if header.start_with?('ADIF') || (header[0] == 0xFF && (header[1] & 0xF0) == 0xF0)
        return '.aac'
      end
    end
    
    # Fallback to extension
    ext = File.extname(file_path).downcase
    return ext if %w[.mp3 .m4a .mp4 .flac .ogg .wav .aac .wma .aiff .alac].include?(ext)
    
    '.unknown'
  end

  def extract_tags_from_file(file_path)
    file_path = Pathname.new(file_path).expand_path
    
    unless File.exist?(file_path)
      return { error: "File not found: #{file_path}" }
    end
    
    unless File.file?(file_path)
      return { error: "Not a file: #{file_path}" }
    end
    
    if File.size(file_path) == 0
      return { error: "Empty file: #{file_path}" }
    end
    
    detected_extension = detect_file_type(file_path)
    
    begin
      tag = WahWah.open(file_path.to_s)
      
      result = {
        file_path: file_path.to_s,
        detected_extension: detected_extension,
        basic_info: extract_basic_info(tag),
        extended_info: extract_extended_info(tag),
        technical_info: extract_technical_info(tag),
        all_tags: extract_all_tags(tag),
        custom_tags: extract_custom_tags(tag)
      }
      
      # Add format-specific info
      case detected_extension
      when '.mp3'
        result[:mp3_specific] = extract_mp3_specific_tags(tag)
      when '.m4a', '.mp4'
        result[:m4a_specific] = extract_m4a_specific_tags(tag)
      when '.flac'
        result[:flac_specific] = extract_flac_specific_tags(tag)
      when '.ogg'
        result[:ogg_specific] = extract_ogg_specific_tags(tag)
      end
      
      result
    rescue => e
      { error: "Failed to extract tags: #{e.message}" }
    end
  end

  def extract_all_tags(tag)
    # Get all available methods on the tag object
    methods = tag.methods - Object.methods
    
    # Extract all tag values
    all_tags = {}
    methods.each do |method|
      next if method.to_s.start_with?('_') # Skip private methods
      next if %w[class object_id inspect to_s to_json].include?(method.to_s)
      
      begin
        value = tag.send(method)
        # Only include non-nil values and skip complex objects
        if value && !value.is_a?(WahWah::Tag) && !value.is_a?(Array)
          all_tags[method.to_s] = value.to_s
        end
      rescue => e
        all_tags[method.to_s] = "ERROR: #{e.message}" if @verbose
      end
    end
    
    all_tags
  end

  def extract_basic_info(tag)
    basic_info = {}
    
    # Try to extract basic info with error handling
    basic_fields = %w[title artist album genre year track total_tracks disc total_discs 
                      comment lyrics composer conductor performer publisher copyright 
                      language grouping]
    
    basic_fields.each do |field|
      begin
        value = tag.send(field) if tag.respond_to?(field)
        basic_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    basic_info
  end

  def extract_extended_info(tag)
    extended_info = {}
    
    # Try to extract extended info with error handling
    extended_fields = %w[duration bitrate sample_rate channels bpm key mood rating 
                         play_count skip_count last_played date_added compilation 
                         gapless lyrics synced_lyrics]
    
    extended_fields.each do |field|
      begin
        value = tag.send(field) if tag.respond_to?(field)
        extended_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    extended_info
  end

  def extract_technical_info(tag)
    technical_info = {}
    
    # Try to extract technical info with error handling
    technical_fields = %w[format codec bitrate_mode variable_bitrate encoder 
                          encoding_settings replay_gain replay_gain_peak]
    
    technical_fields.each do |field|
      begin
        value = tag.send(field) if tag.respond_to?(field)
        technical_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    technical_info
  end

  def extract_custom_tags(tag)
    # Try to extract custom/user-defined tags
    custom_tags = {}
    
    # Common custom tag names
    custom_tag_names = %w[
      custom1 custom2 custom3 custom4 custom5
      user1 user2 user3 user4 user5
      txxx txx1 txx2 txx3 txx4 txx5
      custom_field1 custom_field2 custom_field3
      user_defined1 user_defined2 user_defined3
    ]
    
    custom_tag_names.each do |tag_name|
      begin
        value = tag.send(tag_name) if tag.respond_to?(tag_name)
        custom_tags[tag_name] = value if value
      rescue
        # Ignore errors for custom tags
      end
    end
    
    custom_tags
  end

  def extract_mp3_specific_tags(tag)
    mp3_info = {}
    
    # Try to extract MP3-specific info with error handling
    mp3_fields = %w[id3v1 id3v2 id3v2_version id3v2_flags unsynchronized 
                     extended_header experimental footer_present tag_size padding_size]
    
    mp3_fields.each do |field|
      begin
        if field.end_with?('?')
          value = tag.send(field) if tag.respond_to?(field)
        else
          value = tag.send(field) if tag.respond_to?(field)
        end
        mp3_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    mp3_info
  end

  def extract_m4a_specific_tags(tag)
    m4a_info = {}
    
    # Try to extract M4A-specific info with error handling
    m4a_fields = %w[m4a_atoms itunes_atoms quicktime_atoms atom_count free_atoms metadata_atoms]
    
    m4a_fields.each do |field|
      begin
        if field.end_with?('?')
          value = tag.send(field) if tag.respond_to?(field)
        else
          value = tag.send(field) if tag.respond_to?(field)
        end
        m4a_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    m4a_info
  end

  def extract_flac_specific_tags(tag)
    flac_info = {}
    
    # Try to extract FLAC-specific info with error handling
    flac_fields = %w[flac_metadata_blocks vorbis_comments picture_count seek_table cue_sheet application]
    
    flac_fields.each do |field|
      begin
        if field.end_with?('?')
          value = tag.send(field) if tag.respond_to?(field)
        else
          value = tag.send(field) if tag.respond_to?(field)
        end
        flac_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    flac_info
  end

  def extract_ogg_specific_tags(tag)
    ogg_info = {}
    
    # Try to extract OGG-specific info with error handling
    ogg_fields = %w[vorbis_comments comment_count vendor user_comments]
    
    ogg_fields.each do |field|
      begin
        if field.end_with?('?')
          value = tag.send(field) if tag.respond_to?(field)
        else
          value = tag.send(field) if tag.respond_to?(field)
        end
        ogg_info[field.to_sym] = value if value
      rescue => e
        # Skip fields that cause errors
        next
      end
    end
    
    ogg_info
  end

  def process_directory(directory_path, limit: nil)
    # Handle paths with spaces and special characters
    directory_path = directory_path.gsub('\\', '') # Remove escaped backslashes
    directory = Pathname.new(directory_path).expand_path
    
    begin
      return { error: "Directory not found: #{directory}" } unless directory.exist?
      return { error: "Not a directory: #{directory}" } unless directory.directory?
    rescue Errno::EIO, Errno::ENOENT => e
      return { error: "Cannot access directory #{directory}: #{e.message}" }
    end

    puts "Scanning directory: #{directory}" if @verbose
    
    results = []
    count = 0
    
    begin
      directory.find do |file|
        next unless file.file?
        next if file.size == 0 # Skip empty files
        
        result = extract_tags_from_file(file)
        results << result
        count += 1
        
        if limit && count >= limit
          puts "Reached limit of #{limit} files" if @verbose
          break
        end
      end
    rescue Errno::EIO, Errno::ENOENT => e
      return { error: "Error reading directory #{directory}: #{e.message}" }
    end
    
    {
      directory: directory.to_s,
      total_files_found: count,
      results: results
    }
  end

  def output_result(result)
    case @output_format
    when :json
      puts JSON.pretty_generate(result)
    when :yaml
      require 'yaml'
      puts result.to_yaml
    when :text
      output_text_format(result)
    end
  end

  def output_text_format(result)
    if result[:error]
      puts "ERROR: #{result[:error]}"
      return
    end

    # Handle directory results
    if result[:results]
      puts "=" * 80
      puts "DIRECTORY: #{result[:directory]}"
      puts "TOTAL FILES FOUND: #{result[:total_files_found]}"
      puts "=" * 80
      
      result[:results].each_with_index do |file_result, index|
        puts "\n" + "=" * 80
        puts "FILE #{index + 1}: #{file_result[:file_path]}"
        puts "DETECTED TYPE: #{file_result[:detected_extension]}"
        puts "=" * 80
        
        if file_result[:error]
          puts "ERROR: #{file_result[:error]}"
          next
        end
        
        puts "\nBASIC INFO:"
        puts "-" * 40
        file_result[:basic_info]&.each do |key, value|
          puts "#{key}: #{value}"
        end
        
        puts "\nEXTENDED INFO:"
        puts "-" * 40
        file_result[:extended_info]&.each do |key, value|
          puts "#{key}: #{value}"
        end
        
        puts "\nTECHNICAL INFO:"
        puts "-" * 40
        file_result[:technical_info]&.each do |key, value|
          puts "#{key}: #{value}"
        end
        
        puts "\nALL AVAILABLE TAGS:"
        puts "-" * 40
        file_result[:all_tags]&.each do |key, value|
          puts "#{key}: #{value}"
        end
        
        if file_result[:custom_tags]&.any?
          puts "\nCUSTOM TAGS:"
          puts "-" * 40
          file_result[:custom_tags]&.each do |key, value|
            puts "#{key}: #{value}"
          end
        end
        
        # Format-specific info
        [:mp3_specific, :m4a_specific, :flac_specific, :ogg_specific].each do |format_key|
          if file_result[format_key]&.any?
            puts "\n#{format_key.to_s.upcase}:"
            puts "-" * 40
            file_result[format_key]&.each do |key, value|
              puts "#{key}: #{value}"
            end
          end
        end
      end
      
      puts "\n" + "=" * 80
      return
    end

    # Handle single file results
    puts "=" * 80
    puts "FILE: #{result[:file_path]}"
    puts "DETECTED TYPE: #{result[:detected_extension]}"
    puts "=" * 80
    
    puts "\nBASIC INFO:"
    puts "-" * 40
    result[:basic_info]&.each do |key, value|
      puts "#{key}: #{value}"
    end
    
    puts "\nEXTENDED INFO:"
    puts "-" * 40
    result[:extended_info]&.each do |key, value|
      puts "#{key}: #{value}"
    end
    
    puts "\nTECHNICAL INFO:"
    puts "-" * 40
    result[:technical_info]&.each do |key, value|
      puts "#{key}: #{value}"
    end
    
    puts "\nALL AVAILABLE TAGS:"
    puts "-" * 40
    result[:all_tags]&.each do |key, value|
      puts "#{key}: #{value}"
    end
    
    if result[:custom_tags]&.any?
      puts "\nCUSTOM TAGS:"
      puts "-" * 40
      result[:custom_tags]&.each do |key, value|
        puts "#{key}: #{value}"
      end
    end
    
    # Format-specific info
    [:mp3_specific, :m4a_specific, :flac_specific, :ogg_specific].each do |format_key|
      if result[format_key]&.any?
        puts "\n#{format_key.to_s.upcase}:"
        puts "-" * 40
        result[format_key]&.each do |key, value|
          puts "#{key}: #{value}"
        end
      end
    end
    
    puts "\n" + "=" * 80
  end
end

# Command line interface
def main
  options = {
    verbose: false,
    output_format: :json,
    limit: nil
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby windows_tag_extractor.rb [options] <file_or_directory>"

    opts.on("-v", "--verbose", "Verbose output") do
      options[:verbose] = true
    end

    opts.on("-f", "--format FORMAT", [:json, :yaml, :text], "Output format (json, yaml, text)") do |format|
      options[:output_format] = format
    end

    opts.on("-l", "--limit N", Integer, "Limit number of files to process") do |limit|
      options[:limit] = limit
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts "\nRequirements:"
      puts "  gem install wahwah"
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "Error: Please provide a file or directory path"
    puts "Usage: ruby windows_tag_extractor.rb [options] <file_or_directory>"
    puts "\nRequirements:"
    puts "  gem install wahwah"
    exit 1
  end

  path = ARGV.first
  # Handle paths with escaped characters
  path = path.gsub('\\', '') if path.include?('\\')
  
  extractor = WindowsTagExtractor.new(verbose: options[:verbose], output_format: options[:output_format])

  begin
    if File.directory?(path)
      result = extractor.process_directory(path, limit: options[:limit])
    else
      result = extractor.extract_tags_from_file(path)
    end
  rescue Errno::EIO, Errno::ENOENT => e
    puts "Error: Cannot access path '#{path}': #{e.message}"
    puts "This might be due to:"
    puts "  - Path not existing"
    puts "  - Permission issues"
    puts "  - Network drive not mounted"
    exit 1
  end

  extractor.output_result(result)
end

if __FILE__ == $0
  main
end 