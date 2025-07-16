#!/usr/bin/env ruby
# frozen_string_literal: true

# Storage Tag Extractor - for files without extensions in Rails storage
# Usage: ruby storage_tag_extractor.rb <storage_directory> [options]

require 'optparse'
require 'json'
require 'pathname'
require 'fileutils'

# Add the Rails app to the load path
$LOAD_PATH.unshift(File.expand_path('../archive', __dir__))

# Load Rails environment
ENV['RAILS_ENV'] ||= 'development'
require_relative '../archive/config/environment'

class StorageTagExtractor
  def initialize(verbose: false, output_format: :json)
    @verbose = verbose
    @output_format = output_format
  end

  def detect_file_type(file_path)
    # Read the first few bytes to detect file type
    File.open(file_path, 'rb') do |file|
      header = file.read(12)
      
      case header
      when /^ID3/ # MP3 with ID3 tag
        return '.mp3'
      when /^ftyp/ # MP4/M4A container
        if header.include?('M4A') || header.include?('mp42') || header.include?('isom')
          return '.m4a'
        elsif header.include?('mp4') || header.include?('isom')
          return '.mp4'
        end
      when /^OggS/ # OGG format
        return '.ogg'
      when /^fLaC/ # FLAC format
        return '.flac'
      when /^RIFF.*WAVE/ # WAV format
        return '.wav'
      when /^.{4}ftyp/ # Another MP4 variant
        return '.mp4'
      else
        # Try to detect by file content patterns
        file.seek(0)
        content = file.read(1024)
        
        if content.include?('ID3') || content.include?('TAG')
          return '.mp3'
        elsif content.include?('ftyp') && (content.include?('M4A') || content.include?('mp42'))
          return '.m4a'
        elsif content.include?('OggS')
          return '.ogg'
        elsif content.include?('fLaC')
          return '.flac'
        elsif content.include?('WAVE')
          return '.wav'
        end
      end
    end
    
    # Default to mp3 if we can't detect
    '.mp3'
  end

  def extract_tags_from_file(file_path)
    file_path = Pathname.new(file_path).expand_path
    return { error: "File not found: #{file_path}" } unless file_path.exist?
    return { error: "Not a file: #{file_path}" } unless file_path.file?

    puts "Processing: #{file_path}" if @verbose

    # Detect file type
    detected_ext = detect_file_type(file_path)
    puts "Detected file type: #{detected_ext}" if @verbose

    begin
      require 'wahwah'
      
      # Extract all available tags
      tag = WahWah.open(file_path.to_s)
      
      result = {
        file_path: file_path.to_s,
        filename: file_path.basename.to_s,
        file_size: file_path.size,
        detected_extension: detected_ext,
        content_type: guess_content_type(detected_ext),
        all_tags: extract_all_tags(tag),
        basic_info: extract_basic_info(tag),
        extended_info: extract_extended_info(tag),
        technical_info: extract_technical_info(tag),
        custom_tags: extract_custom_tags(tag)
      }

      # Add format-specific information
      case detected_ext.downcase
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
      {
        file_path: file_path.to_s,
        detected_extension: detected_ext,
        error: "Failed to extract tags: #{e.message}",
        backtrace: @verbose ? e.backtrace.first(5) : nil
      }
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
    {
      title: tag.title,
      artist: tag.artist,
      album: tag.album,
      genre: tag.genre,
      year: tag.year,
      track: tag.track,
      total_tracks: tag.total_tracks,
      disc: tag.disc,
      total_discs: tag.total_discs,
      comment: tag.comment,
      lyrics: tag.lyrics,
      composer: tag.composer,
      conductor: tag.conductor,
      performer: tag.performer,
      publisher: tag.publisher,
      copyright: tag.copyright,
      language: tag.language,
      grouping: tag.grouping
    }.compact
  end

  def extract_extended_info(tag)
    {
      duration: tag.duration,
      bitrate: tag.bitrate,
      sample_rate: tag.sample_rate,
      channels: tag.channels,
      bpm: tag.bpm,
      key: tag.key,
      mood: tag.mood,
      rating: tag.rating,
      play_count: tag.play_count,
      skip_count: tag.skip_count,
      last_played: tag.last_played,
      date_added: tag.date_added,
      compilation: tag.compilation,
      gapless: tag.gapless,
      lyrics: tag.lyrics,
      synced_lyrics: tag.synced_lyrics
    }.compact
  end

  def extract_technical_info(tag)
    {
      format: tag.format,
      codec: tag.codec,
      bitrate_mode: tag.bitrate_mode,
      variable_bitrate: tag.variable_bitrate,
      encoder: tag.encoder,
      encoding_settings: tag.encoding_settings,
      replay_gain: tag.replay_gain,
      replay_gain_peak: tag.replay_gain_peak
    }.compact
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
    {
      id3v1: tag.id3v1?,
      id3v2: tag.id3v2?,
      id3v2_version: tag.id3v2_version,
      id3v2_flags: tag.id3v2_flags,
      unsynchronized: tag.unsynchronized?,
      extended_header: tag.extended_header?,
      experimental: tag.experimental?,
      footer_present: tag.footer_present?,
      tag_size: tag.tag_size,
      padding_size: tag.padding_size
    }.compact
  end

  def extract_m4a_specific_tags(tag)
    {
      m4a_atoms: tag.m4a_atoms?,
      itunes_atoms: tag.itunes_atoms?,
      quicktime_atoms: tag.quicktime_atoms?,
      atom_count: tag.atom_count,
      free_atoms: tag.free_atoms,
      metadata_atoms: tag.metadata_atoms
    }.compact
  end

  def extract_flac_specific_tags(tag)
    {
      flac_metadata_blocks: tag.flac_metadata_blocks?,
      vorbis_comments: tag.vorbis_comments?,
      picture_count: tag.picture_count,
      seek_table: tag.seek_table?,
      cue_sheet: tag.cue_sheet?,
      application: tag.application?
    }.compact
  end

  def extract_ogg_specific_tags(tag)
    {
      vorbis_comments: tag.vorbis_comments?,
      comment_count: tag.comment_count,
      vendor: tag.vendor,
      user_comments: tag.user_comments
    }.compact
  end

  def guess_content_type(extension)
    case extension.downcase
    when '.mp3' then 'audio/mpeg'
    when '.m4a' then 'audio/x-m4a'
    when '.mp4' then 'audio/mp4'
    when '.ogg' then 'audio/ogg'
    when '.flac' then 'audio/flac'
    when '.wav' then 'audio/wav'
    when '.aac' then 'audio/aac'
    when '.wma' then 'audio/x-ms-wma'
    when '.aiff' then 'audio/aiff'
    when '.alac' then 'audio/x-m4a'
    else 'application/octet-stream'
    end
  end

  def process_directory(directory_path, limit: nil)
    directory = Pathname.new(directory_path).expand_path
    return { error: "Directory not found: #{directory}" } unless directory.exist?
    return { error: "Not a directory: #{directory}" } unless directory.directory?

    puts "Scanning directory: #{directory}" if @verbose
    
    results = []
    count = 0
    
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
    opts.banner = "Usage: ruby storage_tag_extractor.rb [options] <file_or_directory>"

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
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "Error: Please provide a file or directory path"
    puts "Usage: ruby storage_tag_extractor.rb [options] <file_or_directory>"
    exit 1
  end

  path = ARGV.first
  extractor = StorageTagExtractor.new(verbose: options[:verbose], output_format: options[:output_format])

  if File.directory?(path)
    result = extractor.process_directory(path, limit: options[:limit])
  else
    result = extractor.extract_tags_from_file(path)
  end

  extractor.output_result(result)
end

if __FILE__ == $0
  main
end 