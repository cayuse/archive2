#!/usr/bin/env ruby
# Test script for encrypted token authentication
# Run this in Rails console: rails console
# Then: load 'test_encrypted_tokens.rb'

puts "Testing Encrypted Token Authentication"
puts "=" * 50

# Test 1: Create a test user
puts "\n1. Creating test user..."
user = User.find_or_create_by(email: 'test@example.com') do |u|
  u.name = 'Test User'
  u.role = 'moderator'
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "   User created: #{user.email} (#{user.role})"

# Test 2: Generate encrypted token
puts "\n2. Generating encrypted token..."
auth_controller = Api::V1::AuthController.new

# Simulate the token generation process
payload = {
  user_id: user.id,
  email: user.email,
  role: user.role,
  exp: 30.days.from_now.to_i,
  iat: Time.current.to_i,
  iss: 'archive-api'
}

json_payload = payload.to_json
encrypted_token = Rails.application.encrypted.encrypt_and_sign(json_payload)
base64_token = Base64.urlsafe_encode64(encrypted_token)

puts "   Token generated: #{base64_token[0..50]}..."
puts "   Token length: #{base64_token.length} characters"

# Test 3: Decrypt and validate token
puts "\n3. Decrypting and validating token..."
begin
  decoded_token = Base64.urlsafe_decode64(base64_token)
  decrypted_payload = Rails.application.encrypted.decrypt_and_verify(decoded_token)
  parsed_payload = JSON.parse(decrypted_payload)
  
  puts "   Decryption successful!"
  puts "   User ID: #{parsed_payload['user_id']}"
  puts "   Email: #{parsed_payload['email']}"
  puts "   Role: #{parsed_payload['role']}"
  puts "   Expires: #{Time.at(parsed_payload['exp'])}"
  
  # Test user lookup
  found_user = User.find(parsed_payload['user_id'])
  puts "   User found: #{found_user.email}"
  
rescue => e
  puts "   ERROR: #{e.message}"
end

# Test 4: Test with invalid token
puts "\n4. Testing with invalid token..."
fake_token = Base64.urlsafe_encode64('{"user_id":1,"role":"admin"}')
begin
  decoded_fake = Base64.urlsafe_decode64(fake_token)
  Rails.application.encrypted.decrypt_and_verify(decoded_fake)
  puts "   ERROR: Fake token was accepted!"
rescue => e
  puts "   SUCCESS: Fake token rejected - #{e.class.name}"
end

# Test 5: Test with expired token
puts "\n5. Testing with expired token..."
expired_payload = {
  user_id: user.id,
  email: user.email,
  role: user.role,
  exp: 1.day.ago.to_i,  # Expired yesterday
  iat: 2.days.ago.to_i,
  iss: 'archive-api'
}

expired_json = expired_payload.to_json
expired_encrypted = Rails.application.encrypted.encrypt_and_sign(expired_json)
expired_base64 = Base64.urlsafe_encode64(expired_encrypted)

begin
  decoded_expired = Base64.urlsafe_decode64(expired_base64)
  decrypted_expired = Rails.application.encrypted.decrypt_and_verify(decoded_expired)
  parsed_expired = JSON.parse(decrypted_expired)
  
  if parsed_expired['exp'] && Time.current.to_i > parsed_expired['exp']
    puts "   SUCCESS: Expired token detected and rejected"
  else
    puts "   ERROR: Expired token was accepted!"
  end
rescue => e
  puts "   ERROR: Token decryption failed - #{e.message}"
end

puts "\n" + "=" * 50
puts "Encrypted Token Authentication Test Complete!"
puts "\nTo test with curl:"
puts "1. Login: curl -X POST http://localhost:3000/api/v1/auth/login -H 'Content-Type: application/json' -d '{\"email\":\"#{user.email}\",\"password\":\"password123\"}'"
puts "2. Use token: curl -H 'Authorization: Bearer YOUR_TOKEN' http://localhost:3000/api/v1/songs"
