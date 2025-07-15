# Testing Guide

This document covers the comprehensive test suite for the Music Archive application.

## 🧪 Test Structure

The application uses Rails' built-in testing framework with Minitest. Tests are organized as follows:

```
test/
├── controllers/          # Controller tests
│   ├── api/v1/          # API controller tests
│   └── sessions_controller_test.rb
├── models/              # Model tests
│   └── song_test.rb
├── jobs/                # Background job tests
│   └── audio_file_processing_job_test.rb
├── fixtures/            # Test data
│   ├── users.yml
│   ├── artists.yml
│   ├── albums.yml
│   ├── genres.yml
│   ├── songs.yml
│   └── files/           # Test files
│       ├── test.mp3
│       └── test.txt
└── test_helper.rb       # Test configuration
```

## 🚀 Running Tests

### Quick Start

Run all tests:
```bash
bin/rails test
```

Run specific test categories:
```bash
# Model tests only
bin/rails test test/models/

# Controller tests only
bin/rails test test/controllers/

# Job tests only
bin/rails test test/jobs/

# API tests only
bin/rails test test/controllers/api/
```

### Using the Test Runner

For a comprehensive test run with summary:
```bash
ruby test_all.rb
```

### Individual Test Files

Run a specific test file:
```bash
bin/rails test test/models/song_test.rb
bin/rails test test/controllers/api/v1/songs_controller_test.rb
bin/rails test test/jobs/audio_file_processing_job_test.rb
```

## 📋 Test Coverage

### Model Tests (`test/models/`)

**Song Model** (`song_test.rb`):
- ✅ Validations (title, user required)
- ✅ Processing status methods
- ✅ Metadata completeness methods
- ✅ Search scopes
- ✅ Processing status scopes
- ✅ Audio file validation
- ✅ Metadata extraction
- ✅ Background job scheduling
- ✅ Associations

### Controller Tests (`test/controllers/`)

**API Songs Controller** (`api/v1/songs_controller_test.rb`):
- ✅ Authentication requirements
- ✅ File upload functionality
- ✅ Metadata handling
- ✅ Bulk operations (create, update, destroy)
- ✅ CSV export
- ✅ Error handling
- ✅ Permission checks
- ✅ Token validation

### Job Tests (`test/jobs/`)

**AudioFileProcessingJob** (`audio_file_processing_job_test.rb`):
- ✅ Metadata extraction and application
- ✅ Error handling
- ✅ Status updates
- ✅ Default record creation
- ✅ Processing state management

## 🎯 Test Categories

### Unit Tests
- **Models**: Test individual model behavior, validations, and methods
- **Jobs**: Test background job processing and error handling
- **Services**: Test business logic in service objects

### Integration Tests
- **Controllers**: Test HTTP endpoints and responses
- **API**: Test API authentication, uploads, and data handling
- **Authentication**: Test login/logout and permission systems

### System Tests
- **User Flows**: Test complete user journeys
- **File Uploads**: Test file processing workflows
- **Search**: Test search functionality

## 🔧 Test Configuration

### Test Helper (`test_helper.rb`)

The test helper includes:
- Parallel test execution
- Fixture loading
- Database cleanup
- Custom assertions

### Fixtures

Test data is defined in YAML fixtures:
- `users.yml`: Test users with different roles
- `artists.yml`: Test artists
- `albums.yml`: Test albums
- `genres.yml`: Test genres
- `songs.yml`: Test songs with different states

### Test Files

Dummy files for testing uploads:
- `test.mp3`: Fake audio file for upload tests
- `test.txt`: Invalid file for error testing

## 🧪 Writing Tests

### Model Test Example

```ruby
class SongTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
  end

  test "should create song with valid attributes" do
    song = Song.new(title: "Test Song", user: @user)
    assert song.save
  end

  test "should require title" do
    song = Song.new(user: @user)
    assert_not song.save
    assert_includes song.errors[:title], "can't be blank"
  end
end
```

### Controller Test Example

```ruby
class Api::V1::SongsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:admin)
    @api_token = create_api_token(@user)
  end

  test "should get index" do
    get api_v1_songs_url, headers: { "Authorization" => "Bearer #{@api_token}" }
    assert_response :success
  end
end
```

### Job Test Example

```ruby
class AudioFileProcessingJobTest < ActiveJob::TestCase
  test "should process song with audio file" do
    song = Song.create!(title: "Test", user: users(:admin))
    song.audio_file.attach(io: StringIO.new("content"), filename: "test.mp3")
    
    assert_changes -> { song.reload.processing_status }, from: 'pending', to: 'completed' do
      AudioFileProcessingJob.perform_now(song.id)
    end
  end
end
```

## 🔍 Test Assertions

### Common Assertions

```ruby
# Basic assertions
assert song.valid?
assert_not song.valid?
assert_equal expected, actual
assert_includes array, item

# Database assertions
assert_difference "Song.count", 1 do
  Song.create!(title: "Test")
end

assert_no_difference "Song.count" do
  # code that shouldn't change count
end

# Change assertions
assert_changes -> { song.reload.status }, from: 'pending', to: 'completed' do
  # code that changes status
end

# Response assertions
assert_response :success
assert_response :created
assert_response :unauthorized
```

## 🚨 Test Best Practices

### 1. **Isolation**
- Each test should be independent
- Use `setup` and `teardown` methods
- Clean up after tests

### 2. **Descriptive Names**
```ruby
test "should create song with valid attributes"
test "should reject invalid audio file"
test "should require authentication for upload"
```

### 3. **Mocking**
- Mock external services
- Mock file operations
- Mock time-dependent operations

### 4. **Fixtures**
- Use fixtures for test data
- Keep fixtures minimal
- Use meaningful fixture names

### 5. **Coverage**
- Test happy paths
- Test error conditions
- Test edge cases
- Test security concerns

## 📊 Test Metrics

### Running with Coverage

To see test coverage:
```bash
# Install simplecov if not already present
gem install simplecov

# Run tests with coverage
COVERAGE=true bin/rails test
```

### Coverage Targets

- **Models**: 95%+
- **Controllers**: 90%+
- **Jobs**: 95%+
- **Overall**: 90%+

## 🔄 Continuous Integration

### GitHub Actions Example

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.3.8
      - name: Install dependencies
        run: bundle install
      - name: Run tests
        run: bin/rails test
```

## 🐛 Debugging Tests

### Verbose Output
```bash
bin/rails test --verbose
```

### Single Test
```bash
bin/rails test test/models/song_test.rb:15
```

### Debug Mode
```bash
bin/rails test --debug
```

## 📝 Adding New Tests

### 1. **Identify What to Test**
- New features
- Bug fixes
- Edge cases
- Security concerns

### 2. **Choose Test Type**
- Unit test for models/services
- Integration test for controllers
- System test for user flows

### 3. **Write Test**
- Follow naming conventions
- Use descriptive test names
- Include setup and assertions

### 4. **Run Test**
- Run individual test first
- Run related test suite
- Run full test suite

## 🎯 Test Priorities

### High Priority
- ✅ Authentication and authorization
- ✅ File uploads and processing
- ✅ API endpoints
- ✅ Background jobs
- ✅ Data validation

### Medium Priority
- ✅ Search functionality
- ✅ Bulk operations
- ✅ Export features
- ✅ Error handling

### Low Priority
- ✅ UI interactions
- ✅ Performance tests
- ✅ Load testing

## 📚 Resources

- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)
- [Minitest Documentation](https://github.com/minitest/minitest)
- [Rails API Testing](https://guides.rubyonrails.org/testing.html#testing-apis) 