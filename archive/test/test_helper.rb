ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    # Mints API tokens exactly as the app does for a logged-in user's page.
    include ApiTokenIssuer

    FIXTURE_PASSWORDS = { "admin" => "admin123", "moderator" => "moderator123", "user" => "user123" }.freeze

    # Log in through the real login form route.
    def sign_in(user, password: FIXTURE_PASSWORDS.fetch(user.role))
      post login_path, params: { email: user.email, password: password }
    end

    # Authorization header for a token-authenticated /api/v1 request.
    def api_headers(user, expires_in: 1.hour)
      { "Authorization" => "Bearer #{api_token_for(user, expires_in: expires_in)}" }
    end
  end
end
