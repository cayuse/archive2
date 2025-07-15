#!/usr/bin/env ruby

# Setup script for Rails application gems and dependencies
# This script ensures all required gems are present in Gemfile

require 'fileutils'

gemfile_path = File.join(__dir__, 'Gemfile')
gemfile_content = File.read(gemfile_path)

# List of gems that should be in the Gemfile
required_gems = [
  'pundit',
  'importmap-rails',
  'turbo-rails'
]

# Check and add missing gems
required_gems.each do |gem_name|
  unless gemfile_content.include?("gem \"#{gem_name}\"")
    puts "Adding gem '#{gem_name}' to Gemfile"
    # Add after the Rails framework gems section
    gemfile_content.gsub!(/(gem "sprockets-rails"\n)/, "\\1gem \"#{gem_name}\"\n")
  else
    puts "Gem '#{gem_name}' already present in Gemfile"
  end
end

# Write back to Gemfile
File.write(gemfile_path, gemfile_content)
puts "Gemfile updated successfully" 