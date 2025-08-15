require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Jukebox
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only run jukebox-specific migrations; core tables are managed by Archive
    config.paths['db/migrate'] = ['db/migrate_jukebox_only']

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Initialize MPD client configuration
    config.after_initialize do
      # Only initialize MPD client if we're running the poller process
      if ENV['FOREMAN_PROCESS_NAME'] == 'poller' || ENV['RAILS_ENV'] == 'development'
        begin
          mpd_host = ENV['MPD_HOST'] || 'localhost'
          mpd_port = (ENV['MPD_PORT'] || 6600).to_i
          mpd_password = ENV['MPD_PASSWORD']
          
          config.mpd_client = MPDClient.new(mpd_host, mpd_port, mpd_password)
          
          # Connect to MPD
          config.mpd_client.connect
          
          Rails.logger.info "MPD client initialized and connected to #{mpd_host}:#{mpd_port}"
          
        rescue => e
          Rails.logger.error "Failed to initialize MPD client: #{e.message}"
          config.mpd_client = nil
        end
      end
    end
  end
end
