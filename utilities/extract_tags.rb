#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple wrapper for the tag extractor
# Usage examples:
#   ruby extract_tags.rb "path/to/file.mp3"
#   ruby extract_tags.rb "path/to/directory" --limit 5 --format text
#   ruby extract_tags.rb "path/to/directory" --verbose --format json

require_relative 'tag_extractor'

# Set up Rails environment
ENV['RAILS_ENV'] ||= 'development'
require_relative '../archive/config/environment'

# Parse command line arguments
verbose = ARGV.include?('--verbose')
format = :json
format = :text if ARGV.include?('--format') && ARGV[ARGV.index('--format') + 1] == 'text'
format = :yaml if ARGV.include?('--format') && ARGV[ARGV.index('--format') + 1] == 'yaml'

limit = nil
if ARGV.include?('--limit')
  limit_index = ARGV.index('--limit')
  limit = ARGV[limit_index + 1].to_i if limit_index && ARGV[limit_index + 1]
end

# Remove options from ARGV
ARGV.reject! { |arg| arg.start_with?('--') }
ARGV.reject! { |arg| arg == 'text' || arg == 'json' || arg == 'yaml' }

if ARGV.empty?
  puts "Usage: ruby extract_tags.rb <file_or_directory> [options]"
  puts ""
  puts "Options:"
  puts "  --verbose          Show detailed output"
  puts "  --format FORMAT    Output format (json, yaml, text)"
  puts "  --limit N          Limit number of files to process"
  puts ""
  puts "Examples:"
  puts "  ruby extract_tags.rb 'C:\\Users\\cayuse\\repaired music\\file.m4a'"
  puts "  ruby extract_tags.rb 'C:\\Users\\cayuse\\repaired music' --limit 10 --format text"
  puts "  ruby extract_tags.rb 'C:\\Users\\cayuse\\repaired music' --verbose --format json"
  exit 1
end

path = ARGV.first
extractor = TagExtractor.new(verbose: verbose, output_format: format)

puts "Extracting tags from: #{path}"
puts "Output format: #{format}"
puts "Verbose: #{verbose}"
puts "Limit: #{limit || 'none'}"
puts "=" * 80

if File.directory?(path)
  result = extractor.process_directory(path, limit: limit)
else
  result = extractor.extract_tags_from_file(path)
end

extractor.output_result(result) 