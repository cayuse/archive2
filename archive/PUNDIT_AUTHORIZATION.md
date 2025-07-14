# Pundit Authorization System

## Overview

This application uses Pundit for role-based authorization with three user roles:
- **User (0)**: Basic users who can create playlists and view content
- **Moderator (1)**: Content moderators who can edit music data
- **Admin (2)**: System administrators with full access

## 🎭 Role Permissions

### User (Basic User)
- ✅ View all music content (artists, albums, songs, genres)
- ✅ Create and manage their own playlists
- ✅ View public playlists
- ✅ Update their own profile
- ❌ Cannot modify core music data
- ❌ Cannot access admin features

### Moderator (Content Moderator)
- ✅ All user permissions
- ✅ Create, edit, and update artists, albums, songs, genres
- ✅ Upload and manage audio files
- ✅ Moderate user content
- ❌ Cannot delete core music data
- ❌ Cannot manage user accounts

### Admin (System Administrator)
- ✅ All moderator permissions
- ✅ Full CRUD operations on all data
- ✅ User account management
- ✅ System configuration
- ✅ Delete any content

## 📁 Policy Files

### ApplicationPolicy (Base Policy)
```ruby
# app/policies/application_policy.rb
- index?: Everyone can view lists
- show?: Everyone can view individual records
- create?: Only moderators and admins
- update?: Only moderators and admins
- destroy?: Only admins
```

### UserPolicy
```ruby
# app/policies/user_policy.rb
- show?: Users can view their own profile
- update?: Users can update their own profile
- create?: Only admins
- destroy?: Only admins (can't delete themselves)
- manage_roles?: Only admins
```

### PlaylistPolicy
```ruby
# app/policies/playlist_policy.rb
- show?: Public playlists or user's own playlists
- create?: Any authenticated user
- update?: User's own playlists
- destroy?: User's own playlists or admins
- manage_songs?: User's own playlists
```

### Content Policies (Artist, Album, Song, Genre)
```ruby
# Inherit from ApplicationPolicy
- index?: Everyone can view
- show?: Everyone can view
- create?: Only moderators and admins
- update?: Only moderators and admins
- destroy?: Only admins
```

## 🔧 Usage in Controllers

### Basic Authorization
```ruby
class ArtistsController < ApplicationController
  before_action :authenticate_user!
  
  def index
    @artists = policy_scope(Artist)
  end
  
  def show
    @artist = Artist.find(params[:id])
    authorize @artist
  end
  
  def new
    @artist = Artist.new
    authorize @artist
  end
  
  def create
    @artist = Artist.new(artist_params)
    authorize @artist
    
    if @artist.save
      redirect_to @artist, notice: 'Artist created successfully.'
    else
      render :new
    end
  end
  
  def edit
    @artist = Artist.find(params[:id])
    authorize @artist
  end
  
  def update
    @artist = Artist.find(params[:id])
    authorize @artist
    
    if @artist.update(artist_params)
      redirect_to @artist, notice: 'Artist updated successfully.'
    else
      render :edit
    end
  end
  
  def destroy
    @artist = Artist.find(params[:id])
    authorize @artist
    
    @artist.destroy
    redirect_to artists_path, notice: 'Artist deleted successfully.'
  end
  
  private
  
  def artist_params
    params.require(:artist).permit(:name, :biography, :country, :formed_year, :website)
  end
end
```

### Custom Authorization Methods
```ruby
class SongsController < ApplicationController
  def upload_audio
    @song = Song.find(params[:id])
    authorize @song, :upload_audio?
    
    # Handle audio upload
  end
  
  def download_audio
    @song = Song.find(params[:id])
    authorize @song, :download_audio?
    
    # Handle audio download
  end
end
```

## 🎨 Usage in Views

### Basic Authorization Checks
```erb
<% if policy(@artist).update? %>
  <%= link_to 'Edit', edit_artist_path(@artist), class: 'btn btn-primary' %>
<% end %>

<% if policy(@artist).destroy? %>
  <%= link_to 'Delete', artist_path(@artist), 
      method: :delete, 
      data: { confirm: 'Are you sure?' },
      class: 'btn btn-danger' %>
<% end %>
```

### Role-Based UI Elements
```erb
<% if can_manage_content? %>
  <div class="admin-panel">
    <h3>Content Management</h3>
    <%= link_to 'Add Artist', new_artist_path, class: 'btn btn-success' %>
    <%= link_to 'Add Album', new_album_path, class: 'btn btn-success' %>
  </div>
<% end %>

<% if can_manage_users? %>
  <div class="admin-panel">
    <h3>User Management</h3>
    <%= link_to 'Manage Users', users_path, class: 'btn btn-warning' %>
  </div>
<% end %>
```

### Playlist-Specific Authorization
```erb
<% @playlists.each do |playlist| %>
  <div class="playlist-card">
    <h4><%= playlist.name %></h4>
    
    <% if policy(playlist).update? %>
      <%= link_to 'Edit', edit_playlist_path(playlist) %>
    <% end %>
    
    <% if policy(playlist).destroy? %>
      <%= link_to 'Delete', playlist_path(playlist), method: :delete %>
    <% end %>
  </div>
<% end %>
```

## 🧪 Testing Policies

### Policy Tests
```ruby
# test/policies/artist_policy_test.rb
require "test_helper"

class ArtistPolicyTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @moderator = users(:moderator)
    @admin = users(:admin)
    @artist = artists(:one)
  end

  def test_user_can_view_artist
    assert ArtistPolicy.new(@user, @artist).show?
  end

  def test_user_cannot_create_artist
    refute ArtistPolicy.new(@user, Artist.new).create?
  end

  def test_moderator_can_create_artist
    assert ArtistPolicy.new(@moderator, Artist.new).create?
  end

  def test_moderator_can_update_artist
    assert ArtistPolicy.new(@moderator, @artist).update?
  end

  def test_moderator_cannot_destroy_artist
    refute ArtistPolicy.new(@moderator, @artist).destroy?
  end

  def test_admin_can_destroy_artist
    assert ArtistPolicy.new(@admin, @artist).destroy?
  end
end
```

### Controller Tests
```ruby
# test/controllers/artists_controller_test.rb
require "test_helper"

class ArtistsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @moderator = users(:moderator)
    @artist = artists(:one)
  end

  test "should get index" do
    get artists_url
    assert_response :success
  end

  test "should get new if moderator" do
    sign_in @moderator
    get new_artist_url
    assert_response :success
  end

  test "should not get new if user" do
    sign_in @user
    get new_artist_url
    assert_redirected_to root_path
  end

  test "should create artist if moderator" do
    sign_in @moderator
    assert_difference('Artist.count') do
      post artists_url, params: { artist: { name: "New Artist" } }
    end
    assert_redirected_to artist_url(Artist.last)
  end
end
```

## 🔒 Security Best Practices

### 1. Always Authorize in Controllers
```ruby
# ✅ Good
def show
  @artist = Artist.find(params[:id])
  authorize @artist
end

# ❌ Bad - No authorization
def show
  @artist = Artist.find(params[:id])
end
```

### 2. Use Policy Scopes for Collections
```ruby
# ✅ Good
def index
  @artists = policy_scope(Artist)
end

# ❌ Bad - No scope
def index
  @artists = Artist.all
end
```

### 3. Check Authorization in Views
```erb
<!-- ✅ Good -->
<% if policy(@artist).update? %>
  <%= link_to 'Edit', edit_artist_path(@artist) %>
<% end %>

<!-- ❌ Bad - No authorization check -->
<%= link_to 'Edit', edit_artist_path(@artist) %>
```

### 4. Handle Authorization Errors
```ruby
# Automatically handled by PunditAuthorization concern
rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

def user_not_authorized
  flash[:alert] = "You are not authorized to perform this action."
  redirect_back(fallback_location: root_path)
end
```

## 🚀 Helper Methods

### Controller Helpers
```ruby
# Available in all controllers
can_manage_content?    # Returns true for moderators and admins
can_manage_users?      # Returns true for admins only
can_upload_audio?      # Returns true for moderators and admins

# Common authorization methods
require_moderator_or_admin  # Redirects if not moderator/admin
require_admin               # Redirects if not admin
require_authenticated_user  # Redirects if not logged in
```

### View Helpers
```erb
<!-- Available in all views -->
<% if can_manage_content? %>
  <!-- Show admin content -->
<% end %>

<% if can_manage_users? %>
  <!-- Show user management -->
<% end %>
```

## 📋 Implementation Checklist

- [x] Install Pundit gem
- [x] Generate policy classes for all models
- [x] Customize ApplicationPolicy with role-based permissions
- [x] Implement model-specific policies
- [x] Create PunditAuthorization concern
- [x] Update ApplicationController
- [x] Add helper methods for views
- [x] Create comprehensive documentation
- [ ] Implement authentication system (sessions/Devise)
- [ ] Add policy tests
- [ ] Add controller tests with authorization
- [ ] Create admin interface
- [ ] Add role management interface

## 🔄 Future Enhancements

### Planned Features
- [ ] Role-based API endpoints
- [ ] Audit logging for admin actions
- [ ] Bulk operations for moderators
- [ ] Advanced permission system
- [ ] Role-based email notifications

### Advanced Authorization
```ruby
# Future: More granular permissions
class ArtistPolicy < ApplicationPolicy
  def manage_biography?
    user&.moderator? || user&.admin?
  end
  
  def manage_discography?
    user&.moderator? || user&.admin?
  end
  
  def manage_media?
    user&.admin?
  end
end
```

---

**Last Updated**: July 2025
**Pundit Version**: 2.5.0
**Rails Version**: 8.0.2 