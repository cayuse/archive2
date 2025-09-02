# JWT Implementation Guide for Archive

## Overview

This guide provides a comprehensive, step-by-step approach to implementing JWT authentication in the Archive system while maintaining production safety and considering the multi-machine sync architecture.

## Architecture Considerations

### Current Setup
- **Master**: Public internet, production system
- **Slaves**: Internal networks, sync with master
- **Test Master**: New machine for testing JWT implementation
- **Sync System**: Existing replication between master/slaves

### JWT Token Strategy
- **Tokens are NOT synced** between master/slaves
- Each machine maintains its own token validity
- Tokens created on master only work on master
- Tokens created on slaves only work on slaves
- This improves security and reduces sync complexity

## Phase 1: Test Environment Setup

### Step 1.1: Create Test Master Machine
```bash
# On your test machine
# 1. Clone the current Archive codebase
git clone <your-archive-repo> archive-jwt-test
cd archive-jwt-test

# 2. Set up as a new master (not connected to production)
# 3. Configure database for testing
# 4. Ensure it's completely isolated from production
```

### Step 1.2: Enable Developer Mode
```bash
# Create a special development container command
# This allows bundle install to run

# Option 1: Docker override
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Option 2: Direct Ruby container
docker run -it --rm \
  -v $(pwd):/app \
  -w /app \
  -p 3000:3000 \
  ruby:3.2-bullseye \
  bash

# Inside container:
bundle install
rails db:create
rails db:migrate
rails db:seed
```

### Step 1.3: Add JWT Gem
```ruby
# Gemfile
gem 'jwt', '~> 2.7'

# Run bundle install
bundle install

# Commit the Gemfile.lock
git add Gemfile.lock
git commit -m "Add JWT gem for secure authentication"
```

## Phase 2: Database Schema Changes

### Step 2.1: Create JWT Token Revocation Table
```ruby
# db/migrate/YYYYMMDDHHMMSS_create_jwt_tokens.rb
class CreateJwtTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :jwt_tokens do |t|
      t.string :jti, null: false, index: { unique: true }
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false # "API Token", "Mobile App", etc.
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.string :ip_address
      t.string :user_agent
      t.boolean :revoked, default: false
      t.datetime :revoked_at
      t.text :revoke_reason
      
      t.timestamps
    end
    
    add_index :jwt_tokens, [:user_id, :revoked]
    add_index :jwt_tokens, :expires_at
  end
end
```

### Step 2.2: Create JWT Token Model
```ruby
# app/models/jwt_token.rb
class JwtToken < ApplicationRecord
  belongs_to :user
  
  validates :jti, presence: true, uniqueness: true
  validates :name, presence: true
  validates :expires_at, presence: true
  
  scope :active, -> { where(revoked: false) }
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :valid, -> { active.where('expires_at > ?', Time.current) }
  
  before_create :generate_jti
  
  def expired?
    expires_at < Time.current
  end
  
  def revoked?
    revoked
  end
  
  def valid?
    !expired? && !revoked?
  end
  
  def revoke!(reason = nil)
    update!(
      revoked: true,
      revoked_at: Time.current,
      revoke_reason: reason
    )
  end
  
  def touch_usage!(request)
    update!(
      last_used_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end
  
  private
  
  def generate_jti
    self.jti = SecureRandom.uuid
  end
end
```

### Step 2.3: Update User Model
```ruby
# app/models/user.rb
class User < ApplicationRecord
  # ... existing code ...
  
  # Add JWT token association
  has_many :jwt_tokens, dependent: :destroy
  
  # Add method to create API tokens
  def create_api_token(name, expires_in: 30.days)
    jwt_tokens.create!(
      name: name,
      expires_at: expires_in.from_now
    )
  end
  
  # Add method to revoke all tokens
  def revoke_all_tokens!
    jwt_tokens.active.update_all(
      revoked: true,
      revoked_at: Time.current,
      revoke_reason: 'User requested revocation'
    )
  end
end
```

### Step 2.4: Run Migration
```bash
# On test machine
rails db:migrate
```

## Phase 3: JWT Service Implementation

### Step 3.1: Create JWT Service
```ruby
# app/services/jwt_service.rb
class JwtService
  ALGORITHM = 'HS256'
  
  class << self
    def encode(payload)
      JWT.encode(payload, secret_key, ALGORITHM)
    end
    
    def decode(token)
      JWT.decode(token, secret_key, true, { algorithm: ALGORITHM })[0]
    rescue JWT::DecodeError, JWT::ExpiredSignature => e
      Rails.logger.error "JWT decode error: #{e.message}"
      nil
    end
    
    def generate_token(user, jti, expires_in: 30.days)
      payload = {
        user_id: user.id,
        email: user.email,
        role: user.role,
        jti: jti,
        exp: expires_in.from_now.to_i,
        iat: Time.current.to_i,
        iss: 'archive-api' # Issuer
      }
      
      encode(payload)
    end
    
    def validate_token(token, request = nil)
      payload = decode(token)
      return nil unless payload
      
      # Check if token is revoked
      jwt_token = JwtToken.find_by(jti: payload['jti'])
      return nil unless jwt_token&.valid?
      
      # Update usage tracking
      jwt_token.touch_usage!(request) if request
      
      # Return user
      jwt_token.user
    end
    
    private
    
    def secret_key
      Rails.application.secret_key_base
    end
  end
end
```

### Step 3.2: Create JWT Authentication Concern
```ruby
# app/controllers/concerns/jwt_authentication.rb
module JwtAuthentication
  extend ActiveSupport::Concern
  
  included do
    before_action :authenticate_jwt_user!, if: :jwt_required?
  end
  
  private
  
  def authenticate_jwt_user!
    token = extract_jwt_token
    
    if token.blank?
      render_jwt_error('Missing JWT token', :unauthorized)
      return
    end
    
    @current_jwt_user = JwtService.validate_token(token, request)
    
    unless @current_jwt_user
      render_jwt_error('Invalid or expired JWT token', :unauthorized)
      return
    end
  end
  
  def extract_jwt_token
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end
  
  def render_jwt_error(message, status)
    render json: {
      success: false,
      message: message,
      error_code: 'JWT_AUTHENTICATION_FAILED'
    }, status: status
  end
  
  def jwt_required?
    # Override in controllers that need JWT
    true
  end
end
```

## Phase 4: Update API Controllers

### Step 4.1: Update Auth Controller
```ruby
# app/controllers/api/v1/auth_controller.rb
class Api::V1::AuthController < ApplicationController
  include JwtAuthentication
  
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_jwt_user!, only: [:login]
  
  def login
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      # Create JWT token record
      jwt_token = user.create_api_token('API Login')
      
      # Generate JWT
      token = JwtService.generate_token(user, jwt_token.jti)
      
      render json: {
        success: true,
        message: "Authentication successful",
        api_token: token,
        token_info: {
          jti: jwt_token.jti,
          expires_at: jwt_token.expires_at.iso8601,
          name: jwt_token.name
        },
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role
        }
      }, status: :ok
    else
      render json: {
        success: false,
        message: "Invalid email or password",
        error_code: 'INVALID_CREDENTIALS'
      }, status: :unauthorized
    end
  end
  
  def logout
    # Revoke current token
    token = extract_jwt_token
    if token
      payload = JwtService.decode(token)
      if payload
        jwt_token = JwtToken.find_by(jti: payload['jti'])
        jwt_token&.revoke!('User logout')
      end
    end
    
    render json: {
      success: true,
      message: "Logged out successfully"
    }, status: :ok
  end
  
  def verify
    render json: {
      success: true,
      message: "JWT token is valid",
      user: {
        id: @current_jwt_user.id,
        name: @current_jwt_user.name,
        email: @current_jwt_user.email,
        role: @current_jwt_user.role
      }
    }, status: :ok
  end
  
  def revoke_token
    token = extract_jwt_token
    if token
      payload = JwtService.decode(token)
      if payload
        jwt_token = JwtToken.find_by(jti: payload['jti'])
        jwt_token&.revoke!(params[:reason] || 'User requested revocation')
      end
    end
    
    render json: {
      success: true,
      message: "Token revoked successfully"
    }, status: :ok
  end
  
  def list_tokens
    tokens = @current_jwt_user.jwt_tokens.active.order(created_at: :desc)
    
    render json: {
      success: true,
      tokens: tokens.map do |token|
        {
          jti: token.jti,
          name: token.name,
          created_at: token.created_at.iso8601,
          expires_at: token.expires_at.iso8601,
          last_used_at: token.last_used_at&.iso8601,
          ip_address: token.ip_address
        }
      end
    }, status: :ok
  end
  
  def revoke_all_tokens
    @current_jwt_user.revoke_all_tokens!
    
    render json: {
      success: true,
      message: "All tokens revoked successfully"
    }, status: :ok
  end
  
  private
  
  def extract_jwt_token
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end
end
```

### Step 4.2: Update Other API Controllers
```ruby
# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ApplicationController
  include JwtAuthentication
  
  skip_before_action :verify_authenticity_token
  
  private
  
  def current_user
    @current_jwt_user
  end
  
  def authenticate_user!
    # JWT authentication is handled by JwtAuthentication concern
  end
end

# Update all API controllers to inherit from BaseController
# app/controllers/api/v1/songs_controller.rb
class Api::V1::SongsController < Api::V1::BaseController
  # Remove old authenticate_api_user! calls
  # JWT authentication is now handled by BaseController
end
```

## Phase 5: Update Routes

### Step 5.1: Add New Auth Routes
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    # Authentication routes
    post '/auth/login', to: 'auth#login'
    post '/auth/logout', to: 'auth#logout'
    get '/auth/verify', to: 'auth#verify'
    post '/auth/revoke_token', to: 'auth#revoke_token'
    get '/auth/tokens', to: 'auth#list_tokens'
    post '/auth/revoke_all_tokens', to: 'auth#revoke_all_tokens'
    
    # ... existing API routes
  end
end
```

## Phase 6: Testing

### Step 6.1: Create Test Scripts
```ruby
# test/jwt_integration_test.rb
require 'test_helper'

class JwtIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:admin)
  end
  
  test "JWT login flow" do
    # Test login
    post '/api/v1/auth/login', params: {
      email: @user.email,
      password: 'password'
    }
    
    assert_response :ok
    response_data = JSON.parse(response.body)
    assert response_data['success']
    assert response_data['api_token']
    assert response_data['token_info']
    
    token = response_data['api_token']
    
    # Test protected endpoint
    get '/api/v1/songs', headers: {
      'Authorization' => "Bearer #{token}"
    }
    
    assert_response :ok
    
    # Test logout
    post '/api/v1/auth/logout', headers: {
      'Authorization' => "Bearer #{token}"
    }
    
    assert_response :ok
    
    # Test that token is now invalid
    get '/api/v1/songs', headers: {
      'Authorization' => "Bearer #{token}"
    }
    
    assert_response :unauthorized
  end
  
  test "JWT token revocation" do
    # Login
    post '/api/v1/auth/login', params: {
      email: @user.email,
      password: 'password'
    }
    
    token = JSON.parse(response.body)['api_token']
    
    # Revoke token
    post '/api/v1/auth/revoke_token', headers: {
      'Authorization' => "Bearer #{token}"
    }
    
    assert_response :ok
    
    # Test that token is now invalid
    get '/api/v1/songs', headers: {
      'Authorization' => "Bearer #{token}"
    }
    
    assert_response :unauthorized
  end
end
```

### Step 6.2: Manual Testing
```bash
# Test JWT login
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "password"}'

# Test protected endpoint
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:3000/api/v1/songs

# Test token revocation
curl -X POST http://localhost:3000/api/v1/auth/revoke_token \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Phase 7: Production Deployment

### Step 7.1: Create Production Migration Script
```ruby
# scripts/production_jwt_migration.rb
# This script will be run on production machines

puts "Starting JWT migration for production..."

# 1. Add JWT gem to Gemfile
gemfile_path = Rails.root.join('Gemfile')
gemfile_content = File.read(gemfile_path)

unless gemfile_content.include?("gem 'jwt'")
  File.open(gemfile_path, 'a') do |f|
    f.puts "gem 'jwt', '~> 2.7'"
  end
  puts "Added JWT gem to Gemfile"
end

# 2. Run migration
system("rails db:migrate")
puts "Database migration completed"

# 3. Create initial JWT tokens for existing users (optional)
User.find_each do |user|
  user.create_api_token('Migration Token', expires_in: 30.days)
end
puts "Created initial JWT tokens for existing users"

puts "JWT migration completed successfully!"
```

### Step 7.2: Create Rollback Script
```ruby
# scripts/jwt_rollback.rb
# Emergency rollback script

puts "Starting JWT rollback..."

# 1. Remove JWT gem from Gemfile
gemfile_path = Rails.root.join('Gemfile')
gemfile_content = File.read(gemfile_path)
new_content = gemfile_content.gsub(/gem 'jwt'.*\n/, '')

File.write(gemfile_path, new_content)
puts "Removed JWT gem from Gemfile"

# 2. Drop JWT tokens table
system("rails db:rollback STEP=1")
puts "Dropped JWT tokens table"

puts "JWT rollback completed!"
```

### Step 7.3: Deployment Steps
```bash
# On each production machine (master and slaves):

# 1. Backup database
pg_dump archive_production > backup_before_jwt_$(date +%Y%m%d_%H%M%S).sql

# 2. Run migration script
ruby scripts/production_jwt_migration.rb

# 3. Restart application
docker-compose restart

# 4. Test JWT endpoints
curl -X POST http://your-archive.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "password"}'
```

## Phase 8: Sync System Considerations

### Step 8.1: Verify Sync Configuration
```ruby
# Check if JWT tokens table should be synced
# Recommendation: DO NOT SYNC JWT tokens

# In your sync configuration, ensure jwt_tokens table is excluded:
# config/sync_exclude_tables = ['jwt_tokens']

# This ensures:
# - Tokens created on master only work on master
# - Tokens created on slaves only work on slaves
# - Better security isolation
# - No sync conflicts
```

### Step 8.2: Update Sync Documentation
```markdown
# JWT Token Sync Policy

## Tables NOT Synced
- `jwt_tokens` - Each machine maintains its own token validity

## Tables Still Synced
- `users` - User accounts and roles
- `songs` - Music library
- `artists` - Artist information
- `albums` - Album information
- `genres` - Genre information
- `playlists` - Playlist data

## Security Benefits
- Tokens are machine-specific
- Compromised token on one machine doesn't affect others
- Better isolation between master and slaves
```

## Phase 9: Monitoring and Maintenance

### Step 9.1: Add JWT Monitoring
```ruby
# app/controllers/concerns/jwt_monitoring.rb
module JwtMonitoring
  extend ActiveSupport::Concern
  
  included do
    after_action :log_jwt_usage
  end
  
  private
  
  def log_jwt_usage
    if @current_jwt_user
      Rails.logger.info "JWT API Access: User #{@current_jwt_user.id} (#{@current_jwt_user.email}) - #{request.method} #{request.path}"
    end
  end
end
```

### Step 9.2: Create JWT Maintenance Tasks
```ruby
# lib/tasks/jwt_maintenance.rake
namespace :jwt do
  desc "Clean up expired JWT tokens"
  task cleanup: :environment do
    expired_count = JwtToken.expired.count
    JwtToken.expired.delete_all
    puts "Cleaned up #{expired_count} expired JWT tokens"
  end
  
  desc "List active JWT tokens"
  task list: :environment do
    JwtToken.valid.includes(:user).find_each do |token|
      puts "#{token.user.email} - #{token.name} - Expires: #{token.expires_at}"
    end
  end
  
  desc "Revoke all tokens for a user"
  task :revoke_user, [:email] => :environment do |t, args|
    user = User.find_by(email: args[:email])
    if user
      user.revoke_all_tokens!
      puts "Revoked all tokens for #{user.email}"
    else
      puts "User not found: #{args[:email]}"
    end
  end
end
```

## Phase 10: Documentation Updates

### Step 10.1: Update API Documentation
```markdown
# Update archive_api.md with JWT examples

## Authentication
All API endpoints require JWT Bearer token authentication.

### Login
POST /api/v1/auth/login
{
  "email": "user@example.com",
  "password": "password"
}

Response:
{
  "success": true,
  "api_token": "eyJhbGciOiJIUzI1NiJ9...",
  "token_info": {
    "jti": "uuid",
    "expires_at": "2023-12-01T00:00:00Z",
    "name": "API Login"
  },
  "user": { ... }
}

### Using JWT Token
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9...
```

## Emergency Procedures

### If JWT Implementation Fails
1. Run rollback script: `ruby scripts/jwt_rollback.rb`
2. Restart application
3. Verify old authentication still works
4. Investigate and fix issues
5. Re-run migration when ready

### If JWT Tokens Are Compromised
1. Revoke all tokens: `rails jwt:revoke_user[admin@example.com]`
2. Force all users to re-login
3. Investigate security breach
4. Update secret key if necessary

## Success Criteria

- [ ] JWT authentication working on test machine
- [ ] All existing API endpoints protected with JWT
- [ ] Token revocation working
- [ ] No sync issues with JWT tokens table
- [ ] Production deployment successful
- [ ] All users can login with JWT
- [ ] Old authentication system removed
- [ ] Monitoring and maintenance tasks working

## Timeline

- **Week 1**: Test environment setup and JWT implementation
- **Week 2**: Testing and validation
- **Week 3**: Production deployment preparation
- **Week 4**: Production deployment and monitoring

This guide ensures a safe, methodical approach to implementing JWT authentication while maintaining production stability and considering your specific architecture requirements.
