#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'
require 'base64'

# Test script for API upload functionality
class ApiUploadTester
  def initialize(base_url = 'http://localhost:3000')
    @base_url = base_url
    @api_base = "#{base_url}/api/v1"
  end

  def test_upload_with_metadata
    puts "Testing API upload with metadata..."
    
    # Create a test token (in real usage, you'd get this from login)
    test_token = create_test_token
    
    # Test data
    test_data = {
      title: "Test Song",
      artist_name: "Test Artist", 
      album_title: "Test Album",
      genre_name: "Test Genre"
    }
    
    # Create a dummy file for testing
    test_file_path = create_test_file
    
    begin
      response = upload_song(test_file_path, test_data, test_token)
      puts "Upload response: #{response}"
      
      if response['success']
        puts "✅ Upload successful!"
        puts "Song ID: #{response['song']['id']}"
        puts "Processing Status: #{response['song']['processing_status']}"
      else
        puts "❌ Upload failed: #{response['message']}"
      end
      
    rescue => e
      puts "❌ Error during upload: #{e.message}"
    ensure
      # Clean up test file
      File.delete(test_file_path) if File.exist?(test_file_path)
    end
  end

  private

  def create_test_token
    # This is a simplified test token - in production you'd get this from login
    payload = {
      user_id: 1, # Assuming user ID 1 exists
      exp: Time.now.to_i + 3600 # 1 hour from now
    }
    
    Base64.urlsafe_encode64(payload.to_json)
  end

  def create_test_file
    test_file = Tempfile.new(['test_song', '.mp3'])
    test_file.write("fake mp3 content")
    test_file.close
    test_file.path
  end

  def upload_song(file_path, metadata, token)
    uri = URI("#{@api_base}/songs/bulk_upload")
    
    # Create multipart form data
    boundary = "boundary#{rand(1000000)}"
    
    post_data = []
    post_data << "--#{boundary}"
    post_data << "Content-Disposition: form-data; name=\"audio_file\"; filename=\"#{File.basename(file_path)}\""
    post_data << "Content-Type: audio/mpeg"
    post_data << ""
    post_data << File.read(file_path)
    
    # Add metadata parameters
    metadata.each do |key, value|
      post_data << "--#{boundary}"
      post_data << "Content-Disposition: form-data; name=\"#{key}\""
      post_data << ""
      post_data << value.to_s
    end
    
    post_data << "--#{boundary}--"
    post_data << ""
    
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    request.body = post_data.join("\r\n")
    
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
    
    JSON.parse(response.body)
  end
end

# Run the test
if __FILE__ == $0
  tester = ApiUploadTester.new
  tester.test_upload_with_metadata
end 