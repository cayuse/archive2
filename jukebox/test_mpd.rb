#!/usr/bin/env ruby

# Simple test script for MPD client
# Run with: ruby test_mpd.rb

require_relative 'lib/mpd_client'

puts "Testing MPD Client..."

begin
  # Initialize client
  client = MpdClient.new('localhost', 6600)
puts "✓ MpdClient initialized"
  
  # Try to connect
  client.connect
  puts "✓ Connected to MPD"
  
  # Test basic operations
  status = client.get_status
  puts "✓ Got status: #{status[:state]}"
  
  volume = client.get_volume
  puts "✓ Got volume: #{volume[:volume]}%"
  
  queue = client.get_queue
  puts "✓ Got queue length: #{queue[:length]}"
  
  # Test volume change
  result = client.set_volume(80)
  puts "✓ Set volume: #{result[:volume]}%"
  
  puts "\n🎉 All tests passed! MPD client is working correctly."
  
rescue => e
  puts "❌ Test failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
