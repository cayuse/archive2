# Quick Security Fix: Rails Encryption for API Tokens

## Overview

This is a temporary security fix that uses Rails built-in encryption with the master key to secure API tokens. This prevents users from creating their own tokens or modifying existing ones.

## Benefits

- ✅ **Uses existing Rails infrastructure** - No new gems needed
- ✅ **Master key based** - Tokens only valid on the machine that created them
- ✅ **Two-way encryption** - Can't be tampered with
- ✅ **Easy to implement** - Minimal code changes
- ✅ **Easy to rotate** - Change master key to invalidate all tokens
- ✅ **No database changes** - Works with existing system

## Implementation

### Step 1: Update Auth Controller

```ruby
# app/controllers/api/v1/auth_controller.rb
class Api::V1::AuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!, only: [:verify, :logout]

  def login
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      # Generate encrypted API token
      api_token = generate_encrypted_token(user)
      
      render json: {
        success: true,
        message: "Authentication successful",
        api_token: api_token,
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
        message: "Invalid email or password"
      }, status: :unauthorized
    end
  end

  def logout
    # In a real implementation, you might want to invalidate the token
    # For now, we'll just return a success message
    render json: {
      success: true,
      message: "Logged out successfully"
    }, status: :ok
  end

  def verify
    # This endpoint is used to verify API tokens
    render json: {
      success: true,
      message: "API token is valid",
      user: {
        id: @current_api_user.id,
        name: @current_api_user.name,
        email: @current_api_user.email,
        role: @current_api_user.role
      }
    }, status: :ok
  end

  private

  def generate_encrypted_token(user)
    # Create payload with user info and expiration
    payload = {
      user_id: user.id,
      email: user.email,
      role: user.role,
      exp: 30.days.from_now.to_i,
      iat: Time.current.to_i,
      iss: 'archive-api'
    }
    
    # Convert to JSON and encrypt with Rails master key
    json_payload = payload.to_json
    encrypted_token = Rails.application.encryptor.encrypt_and_sign(json_payload)
    
    # Base64 encode for URL safety
    Base64.urlsafe_encode64(encrypted_token)
  end

  def authenticate_api_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { success: false, message: "Missing API token" }, status: :unauthorized
      return
    end

    begin
      # Decode from Base64
      decoded_token = Base64.urlsafe_decode64(token)
      
      # Decrypt with Rails master key
      decrypted_payload = Rails.application.encryptor.decrypt_and_verify(decoded_token)
      
      # Parse JSON payload
      payload = JSON.parse(decrypted_payload)
      
      # Check if token is expired
      if payload['exp'] && Time.current.to_i > payload['exp']
        render json: { success: false, message: "API token expired" }, status: :unauthorized
        return
      end
      
      # Find the user
      @current_api_user = User.find(payload['user_id'])
      
      unless @current_api_user
        render json: { success: false, message: "Invalid API token" }, status: :unauthorized
        return
      end
      
    rescue => e
      Rails.logger.error "Token decryption error: #{e.message}"
      render json: { success: false, message: "Invalid API token" }, status: :unauthorized
      return
    end
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    # Extract token from "Bearer <token>" format
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end
end
```

### Step 2: Update Other API Controllers

```ruby
# app/controllers/api/v1/songs_controller.rb
class Api::V1::SongsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!
  before_action :ensure_upload_permission!

  # ... rest of controller methods remain the same

  private

  def authenticate_api_user!
    # This method is now in the auth controller, but we need it here too
    # Copy the method from auth_controller.rb or create a concern
  end

  def ensure_upload_permission!
    unless @current_api_user.moderator? || @current_api_user.admin?
      render json: {
        success: false,
        message: "Insufficient permissions for upload"
      }, status: :forbidden
      return
    end
  end
end
```

### Step 3: Create Authentication Concern (Better Approach)

```ruby
# app/controllers/concerns/encrypted_token_authentication.rb
module EncryptedTokenAuthentication
  extend ActiveSupport::Concern
  
  included do
    before_action :authenticate_encrypted_token_user!
  end
  
  private
  
  def authenticate_encrypted_token_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { success: false, message: "Missing API token" }, status: :unauthorized
      return
    end

    begin
      # Decode from Base64
      decoded_token = Base64.urlsafe_decode64(token)
      
      # Decrypt with Rails master key
      decrypted_payload = Rails.application.encryptor.decrypt_and_verify(decoded_token)
      
      # Parse JSON payload
      payload = JSON.parse(decrypted_payload)
      
      # Check if token is expired
      if payload['exp'] && Time.current.to_i > payload['exp']
        render json: { success: false, message: "API token expired" }, status: :unauthorized
        return
      end
      
      # Find the user
      @current_api_user = User.find(payload['user_id'])
      
      unless @current_api_user
        render json: { success: false, message: "Invalid API token" }, status: :unauthorized
        return
      end
      
    rescue => e
      Rails.logger.error "Token decryption error: #{e.message}"
      render json: { success: false, message: "Invalid API token" }, status: :unauthorized
      return
    end
  end
  
  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    # Extract token from "Bearer <token>" format
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end
end
```

### Step 4: Update Controllers to Use Concern

```ruby
# app/controllers/api/v1/songs_controller.rb
class Api::V1::SongsController < ApplicationController
  include EncryptedTokenAuthentication
  
  skip_before_action :verify_authenticity_token
  before_action :ensure_upload_permission!

  # ... rest of controller methods remain the same

  private

  def ensure_upload_permission!
    unless @current_api_user.moderator? || @current_api_user.admin?
      render json: {
        success: false,
        message: "Insufficient permissions for upload"
      }, status: :forbidden
      return
    end
  end
end

# app/controllers/api/v1/playlists_controller.rb
class Api::V1::PlaylistsController < ApplicationController
  include EncryptedTokenAuthentication
  
  skip_before_action :verify_authenticity_token
  
  # ... rest of controller methods remain the same
end

# app/controllers/api/v1/audio_files_controller.rb
class Api::V1::AudioFilesController < ApplicationController
  include EncryptedTokenAuthentication
  
  skip_before_action :verify_authenticity_token
  
  # ... rest of controller methods remain the same
end
```

## Security Analysis

### **What This Fixes:**
- ✅ **Tamper-proof tokens** - Can't modify user_id, role, etc.
- ✅ **Machine-specific** - Tokens only work on the machine that created them
- ✅ **No token creation** - Users can't create their own tokens
- ✅ **Easy rotation** - Change master key to invalidate all tokens
- ✅ **Expiration handling** - Built-in token expiration

### **How It Works:**
1. **Token Creation**: User data + expiration → JSON → Rails encryption → Base64
2. **Token Validation**: Base64 → Rails decryption → JSON → User lookup
3. **Security**: Uses Rails master key for encryption/decryption

### **Attack Scenarios Now Prevented:**
```bash
# This no longer works:
payload='{"user_id":1,"email":"admin@example.com","role":"admin","exp":9999999999}'
admin_token=$(echo -n "$payload" | base64)

# Because the token must be encrypted with the master key
# Users can't create valid tokens without the master key
```

## Testing

### **Test Token Creation:**
```bash
# Login to get encrypted token
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@example.com", "password": "password"}'

# Use the encrypted token
curl -H "Authorization: Bearer ENCRYPTED_TOKEN" \
  http://localhost:3000/api/v1/songs
```

### **Test Token Security:**
```bash
# Try to create a fake token (should fail)
fake_token=$(echo -n '{"user_id":1,"role":"admin"}' | base64)
curl -H "Authorization: Bearer $fake_token" \
  http://localhost:3000/api/v1/songs
# Should return: "Invalid API token"
```

## Master Key Rotation

### **To Invalidate All Tokens:**
```bash
# 1. Generate new master key
openssl rand -hex 32

# 2. Update config/master.key
echo "new_master_key_here" > config/master.key

# 3. Restart application
docker-compose restart

# 4. All existing tokens are now invalid
# Users must re-login to get new tokens
```

## Deployment Steps

### **Step 1: Update Code**
```bash
# 1. Update auth_controller.rb with encrypted token methods
# 2. Create encrypted_token_authentication.rb concern
# 3. Update all API controllers to use the concern
# 4. Test on development machine
```

### **Step 2: Deploy to Production**
```bash
# 1. Deploy updated code
# 2. Restart application
# 3. Test login and API access
# 4. Verify old tokens no longer work
```

### **Step 3: Monitor**
```bash
# Check logs for token decryption errors
tail -f log/production.log | grep "Token decryption error"
```

## Advantages Over JWT

- ✅ **No new dependencies** - Uses existing Rails infrastructure
- ✅ **Simpler implementation** - Less code to maintain
- ✅ **Master key based** - Easy to rotate and invalidate tokens
- ✅ **Machine-specific** - Tokens only work on the machine that created them
- ✅ **No database changes** - Works with existing system

## Disadvantages vs JWT

- ❌ **Not industry standard** - Custom implementation
- ❌ **No built-in revocation** - Must rotate master key to revoke all tokens
- ❌ **Larger tokens** - Encrypted tokens are larger than JWT
- ❌ **Rails-specific** - Not portable to other frameworks

## Recommendation

This is an **excellent temporary fix** that provides immediate security while you plan the full JWT implementation. It's:

- **Quick to implement** (1-2 hours)
- **Secure enough** for production use
- **Easy to maintain** 
- **Simple to understand**

You can implement this now for immediate security, then plan the full JWT implementation for later when you have more time.
