#!/usr/bin/env ruby

require 'fileutils'
require 'optparse'

# Helper script to copy files from Windows to Docker container
class WindowsFileCopier
  def initialize(source_path, dest_path, limit: nil, file_types: %w[mp3 m4a flac wav aac ogg])
    @source_path = source_path
    @dest_path = dest_path
    @limit = limit
    @file_types = file_types
  end

  def copy_files
    puts "Copying files from #{@source_path} to #{@dest_path}"
    puts "File types: #{@file_types.join(', ')}"
    puts "Limit: #{@limit || 'unlimited'}"
    
    # Create destination directory
    FileUtils.mkdir_p(@dest_path)
    
    copied_count = 0
    skipped_count = 0
    
    begin
      Dir.glob(File.join(@source_path, "**/*")).each do |file|
        next unless File.file?(file)
        
        # Check file extension
        ext = File.extname(file).downcase[1..-1]
        next unless @file_types.include?(ext)
        
        # Create relative path structure
        relative_path = Pathname.new(file).relative_path_from(Pathname.new(@source_path))
        dest_file = File.join(@dest_path, relative_path)
        
        # Create destination directory
        FileUtils.mkdir_p(File.dirname(dest_file))
        
        # Copy file
        FileUtils.cp(file, dest_file)
        puts "Copied: #{relative_path}"
        copied_count += 1
        
        if @limit && copied_count >= @limit
          puts "Reached limit of #{@limit} files"
          break
        end
      rescue => e
        puts "Error copying #{file}: #{e.message}"
        skipped_count += 1
      end
    rescue => e
      puts "Error accessing source directory: #{e.message}"
      return false
    end
    
    puts "\nSummary:"
    puts "  Copied: #{copied_count} files"
    puts "  Skipped: #{skipped_count} files"
    puts "  Destination: #{@dest_path}"
    
    true
  end
end

def main
  options = {
    limit: nil,
    file_types: %w[mp3 m4a flac wav aac ogg],
    dest_path: "/workspaces/dockercrap/temp_analysis"
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby copy_windows_files.rb [options] <source_path>"

    opts.on("-d", "--dest PATH", "Destination path (default: /workspaces/dockercrap/temp_analysis)") do |path|
      options[:dest_path] = path
    end

    opts.on("-l", "--limit N", Integer, "Limit number of files to copy") do |limit|
      options[:limit] = limit
    end

    opts.on("-t", "--types TYPES", Array, "File types to copy (default: mp3,m4a,flac,wav,aac,ogg)") do |types|
      options[:file_types] = types
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!

  if ARGV.empty?
    puts "Error: Please provide a source path"
    puts "Usage: ruby copy_windows_files.rb [options] <source_path>"
    exit 1
  end

  source_path = ARGV.first
  
  # Handle Windows paths
  source_path = source_path.gsub('\\', '') if source_path.include?('\\')
  
  unless Dir.exist?(source_path)
    puts "Error: Source directory does not exist: #{source_path}"
    puts "Note: Docker containers may not have access to Windows filesystem"
    puts "You may need to mount the directory or copy files manually"
    exit 1
  end

  copier = WindowsFileCopier.new(
    source_path, 
    options[:dest_path], 
    limit: options[:limit], 
    file_types: options[:file_types]
  )

  if copier.copy_files
    puts "\nNow you can analyze the files with:"
    puts "ruby standalone_tag_extractor.rb #{options[:dest_path]} --limit 5 --format text"
  else
    puts "Failed to copy files"
    exit 1
  end
end

if __FILE__ == $0
  main
end 