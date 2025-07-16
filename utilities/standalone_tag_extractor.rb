#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone Tag Extractor - works without Rails
# Usage: ruby standalone_tag_extractor.rb <file_or_directory> [options]
#
# Requirements:
#   gem install wahwah
#   gem install json (usually included with Ruby)

require 'optparse'
require 'json'
require 'pathname'
require 'fileutils'

# Check if wahwah gem is available
begin
  require 'wahwah'
rescue LoadError
  puts "ERROR: wahwah gem not found!"
  puts "Please install it with: gem install wahwah"
  puts "Or add it to your Gemfile: gem 'wahwah'"
  exit 1
end

class StandaloneTagExtractor
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
      # Extract all available tags using wahwah
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
        custom_tags: extract_custom_tags(tag),
        image_info: extract_image_info(tag)
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

      # Also try to extract metadata using ffprobe for more comprehensive data
      ffprobe_data = extract_ffprobe_metadata(file_path)
      result[:ffprobe_metadata] = ffprobe_data if ffprobe_data

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

  def extract_ffprobe_metadata(file_path)
    begin
      require 'json'
      
      # Run ffprobe to get comprehensive metadata
      cmd = "ffprobe -v quiet -print_format json -show_format -show_streams \"#{file_path}\""
      output = `#{cmd}`
      
      return nil if output.empty? || $?.exitstatus != 0
      
      data = JSON.parse(output)
      
      # Extract metadata from format tags
      metadata = {}
      if data['format'] && data['format']['tags']
        metadata.merge!(data['format']['tags'])
      end
      
      # Extract metadata from stream tags
      if data['streams']
        data['streams'].each_with_index do |stream, index|
          if stream['tags']
            stream['tags'].each do |key, value|
              metadata["stream_#{index}_#{key}"] = value
            end
          end
        end
      end
      
      # Add format info
      if data['format']
        metadata['format_name'] = data['format']['format_name']
        metadata['format_long_name'] = data['format']['format_long_name']
        metadata['duration'] = data['format']['duration']
        metadata['size'] = data['format']['size']
        metadata['bit_rate'] = data['format']['bit_rate']
      end
      
      metadata
    rescue => e
      puts "Warning: Could not extract ffprobe metadata: #{e.message}" if @verbose
      nil
    end
  end

  def extract_all_tags(tag)
    # Get all available methods on the tag object
    methods = tag.methods - Object.methods
    
    # Extract ALL tag values - no filtering
    all_tags = {}
    methods.each do |method|
      next if method.to_s.start_with?('_') # Skip private methods
      next if %w[class object_id inspect to_s to_json].include?(method.to_s)
      
      # Skip image-related methods as they're handled separately
      next if %w[images picture pictures artwork cover front_cover back_cover image album_art album_cover].include?(method.to_s)
      
      begin
        value = tag.send(method)
        
        # Handle different types of values
        if value
          if value.is_a?(Array)
            # For arrays, show all items
            if value.empty?
              all_tags[method.to_s] = "[] (empty array)"
            else
              # Show all array items, not just first 3
              items = value.map(&:to_s).join(", ")
              all_tags[method.to_s] = "[#{value.length} items: #{items}]"
            end
          elsif value.is_a?(WahWah::Tag)
            # Skip nested tag objects
            next
          elsif value.is_a?(String) && value.encoding == Encoding::BINARY
            # Skip binary data from all_tags section
            next
          elsif value.is_a?(String) && value.bytesize > 1000
            # Handle large strings - truncate them
            all_tags[method.to_s] = "#{value[0..1000]}... (truncated, total: #{value.bytesize} bytes)"
          else
            # Regular values - include everything, even empty strings
            all_tags[method.to_s] = value.to_s
          end
        else
          # Include nil values too
          all_tags[method.to_s] = "nil"
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
    
    # Also try to extract comments from different possible sources
    comment_sources = %w[comment comments user_comment user_comments]
    comment_sources.each do |source|
      begin
        if tag.respond_to?(source)
          value = tag.send(source)
          if value && !basic_info[:comment]
            basic_info[:comment] = value
          end
        end
      rescue => e
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
    # Try to extract ALL possible custom/user-defined tags
    custom_tags = {}
    
    # Common custom tag names and variations
    custom_tag_names = %w[
      custom1 custom2 custom3 custom4 custom5
      user1 user2 user3 user4 user5
      txxx txx1 txx2 txx3 txx4 txx5
      custom_field1 custom_field2 custom_field3
      user_defined1 user_defined2 user_defined3
      comment comments user_comment user_comments
      description desc
      notes note
      lyrics synced_lyrics unsynced_lyrics
      copyright copr
      publisher pub
      composer comp
      conductor cond
      performer perf
      arranger arr
      engineer eng
      producer prod
      mixer mix
      remixer remix
      dj dj_name
      label lbl
      catalog cat
      isrc isrc_code
      barcode upc ean
      discid disc_id
      musicbrainz musicbrainz_id mb_id
      acoustid acoustid_id
      freedb freedb_id
      playcount play_count
      rating rate
      mood emotion
      tempo bpm
      key musical_key
      genre subgenre style
      language lang
      country cnt
      year date recorded_date
      original_year original_date
      release_date
      recording_date
      mastering_date
      compilation comp
      live live_recording
      remaster remastered
      version ver
      mix_name mix_title
      original_artist original_artist_name
      featuring feat ft
      guest guest_artist
      collaboration collab
      tribute tribute_to
      cover cover_version
      remix remix_of
      sample sampled_from
      interpolation interpolates
      medley medley_of
      suite suite_of
      movement movement_of
      part part_of
      volume vol
      disc disc_number
      track track_number
      side side_a side_b
      bonus bonus_track
      hidden hidden_track
      secret secret_track
      intro intro_track
      outro outro_track
      interlude interlude_track
      instrumental instrumental_version
      acapella acapella_version
      karaoke karaoke_version
      demo demo_version
      rehearsal rehearsal_version
      soundcheck soundcheck_version
      radio radio_edit
      single single_version
      album album_version
      extended extended_version
      club club_mix
      dub dub_mix
      instrumental instrumental_mix
      vocal vocal_mix
      radio radio_mix
      club club_edit
      radio radio_edit
      single single_edit
      album album_edit
      extended extended_edit
      original original_mix
      remix remix_mix
      edit edit_mix
      instrumental instrumental_edit
      vocal vocal_edit
      acapella acapella_edit
      karaoke karaoke_edit
      demo demo_edit
      rehearsal rehearsal_edit
      soundcheck soundcheck_edit
      live live_edit
      studio studio_edit
      unplugged unplugged_edit
      acoustic acoustic_edit
      electric electric_edit
      electronic electronic_edit
      classical classical_edit
      jazz jazz_edit
      blues blues_edit
      country country_edit
      folk folk_edit
      rock rock_edit
      pop pop_edit
      hip_hop hip_hop_edit
      rap rap_edit
      rnb rnb_edit
      soul soul_edit
      funk funk_edit
      disco disco_edit
      house house_edit
      techno techno_edit
      trance trance_edit
      ambient ambient_edit
      new_age new_age_edit
      world world_edit
      reggae reggae_edit
      ska ska_edit
      punk punk_edit
      metal metal_edit
      hardcore hardcore_edit
      emo emo_edit
      indie indie_edit
      alternative alternative_edit
      experimental experimental_edit
      avant_garde avant_garde_edit
      noise noise_edit
      industrial industrial_edit
      gothic gothic_edit
      dark dark_edit
      chillout chillout_edit
      lounge lounge_edit
      downtempo downtempo_edit
      trip_hop trip_hop_edit
      drum_n_bass drum_n_bass_edit
      jungle jungle_edit
      garage garage_edit
      grime grime_edit
      dubstep dubstep_edit
      breakbeat breakbeat_edit
      big_beat big_beat_edit
      acid acid_edit
      progressive progressive_edit
      psytrance psytrance_edit
      goa goa_edit
      minimal minimal_edit
      deep deep_edit
      tech tech_edit
      electro electro_edit
      synthpop synthpop_edit
      new_wave new_wave_edit
      post_punk post_punk_edit
      goth goth_edit
      darkwave darkwave_edit
      ethereal ethereal_edit
      shoegaze shoegaze_edit
      dream_pop dream_pop_edit
      slowcore slowcore_edit
      sadcore sadcore_edit
      post_rock post_rock_edit
      math_rock math_rock_edit
      emo_rock emo_rock_edit
      screamo screamo_edit
      post_hardcore post_hardcore_edit
      metalcore metalcore_edit
      deathcore deathcore_edit
      grindcore grindcore_edit
      black_metal black_metal_edit
      death_metal death_metal_edit
      thrash_metal thrash_metal_edit
      power_metal power_metal_edit
      progressive_metal progressive_metal_edit
      symphonic_metal symphonic_metal_edit
      folk_metal folk_metal_edit
      pagan_metal pagan_metal_edit
      viking_metal viking_metal_edit
      doom_metal doom_metal_edit
      sludge_metal sludge_metal_edit
      stoner_metal stoner_metal_edit
      drone_metal drone_metal_edit
      post_metal post_metal_edit
      industrial_metal industrial_metal_edit
      nu_metal nu_metal_edit
      rap_metal rap_metal_edit
      funk_metal funk_metal_edit
      jazz_metal jazz_metal_edit
      classical_metal classical_metal_edit
      electronic_metal electronic_metal_edit
      experimental_metal experimental_metal_edit
      avant_metal avant_metal_edit
      noise_metal noise_metal_edit
      gothic_metal gothic_metal_edit
      dark_metal dark_metal_edit
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

  def extract_image_info(tag)
    # Extract information about embedded images/artwork
    image_info = {}
    
    # Common image-related methods
    image_methods = %w[
      picture pictures artwork cover front_cover back_cover
      image images album_art album_cover
    ]
    
    image_methods.each do |method|
      begin
        if tag.respond_to?(method)
          value = tag.send(method)
          if value
            if value.is_a?(Array)
              # Handle array of images
              image_info[method.to_sym] = "#{value.length} images found"
              
              # Show details for each image
              value.each_with_index do |img, index|
                if img.respond_to?(:mime_type) && img.respond_to?(:type)
                  image_info["#{method}_#{index + 1}_mime_type".to_sym] = img.mime_type
                  image_info["#{method}_#{index + 1}_type".to_sym] = img.type
                  image_info["#{method}_#{index + 1}_size".to_sym] = "#{img.data.bytesize} bytes" if img.respond_to?(:data)
                end
              end
            elsif value.is_a?(String) && value.encoding == Encoding::BINARY
              image_info[method.to_sym] = "Binary image data (#{value.bytesize} bytes)"
            else
              image_info[method.to_sym] = value.to_s
            end
          end
        end
      rescue => e
        image_info[method.to_sym] = "Error: #{e.message}" if @verbose
      end
    end
    
    image_info
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
    when :grep
      output_grep_format(result)
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
        
        if file_result[:image_info]&.any?
          puts "\nIMAGE INFO:"
          puts "-" * 40
          file_result[:image_info]&.each do |key, value|
            puts "#{key}: #{value}"
          end
        end
        
        if file_result[:ffprobe_metadata]&.any?
          puts "\nFFPROBE METADATA:"
          puts "-" * 40
          file_result[:ffprobe_metadata]&.each do |key, value|
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
    
    if result[:image_info]&.any?
      puts "\nIMAGE INFO:"
      puts "-" * 40
      result[:image_info]&.each do |key, value|
        puts "#{key}: #{value}"
      end
    end
    
    if result[:ffprobe_metadata]&.any?
      puts "\nFFPROBE METADATA:"
      puts "-" * 40
      result[:ffprobe_metadata]&.each do |key, value|
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

  def output_grep_format(result)
    if result[:error]
      puts "ERROR: #{result[:error]}"
      return
    end

    # Handle directory results
    if result[:results]
      result[:results].each do |file_result|
        next if file_result[:error]
        
        file_path = file_result[:file_path]
        
        # Show comments
        if file_result[:basic_info]&.dig(:comment)
          puts "#{file_path}: comment: #{file_result[:basic_info][:comment]}"
        end
        
        # Show all non-empty tags
        file_result[:all_tags]&.each do |key, value|
          puts "#{file_path}: #{key}: #{value}"
        end
        
        # Show ffprobe metadata
        file_result[:ffprobe_metadata]&.each do |key, value|
          puts "#{file_path}: ffprobe_#{key}: #{value}"
        end
      end
      return
    end

    # Handle single file results
    file_path = result[:file_path]
    
    # Show comments
    if result[:basic_info]&.dig(:comment)
      puts "#{file_path}: comment: #{result[:basic_info][:comment]}"
    end
    
    # Show all non-empty tags
    result[:all_tags]&.each do |key, value|
      puts "#{file_path}: #{key}: #{value}"
    end
    
    # Show ffprobe metadata
    result[:ffprobe_metadata]&.each do |key, value|
      puts "#{file_path}: ffprobe_#{key}: #{value}"
    end
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
    opts.banner = "Usage: ruby standalone_tag_extractor.rb [options] <file_or_directory>"

    opts.on("-v", "--verbose", "Verbose output") do
      options[:verbose] = true
    end

    opts.on("-f", "--format FORMAT", [:json, :yaml, :text, :grep], "Output format (json, yaml, text, grep)") do |format|
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
    puts "Usage: ruby standalone_tag_extractor.rb [options] <file_or_directory>"
    puts "\nRequirements:"
    puts "  gem install wahwah"
    exit 1
  end

  path = ARGV.first
  # Handle paths with escaped characters
  path = path.gsub('\\', '') if path.include?('\\')
  
  extractor = StandaloneTagExtractor.new(verbose: options[:verbose], output_format: options[:output_format])

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
    puts "  - Docker container cannot access the host filesystem"
    exit 1
  end

  extractor.output_result(result)
end

if __FILE__ == $0
  main
end 