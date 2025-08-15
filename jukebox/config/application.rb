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
    config.autoload_lib(ignore: %w(assets tasks))

    # Disable Zeitwerk and use classic autoloader to fix MPD client loading issues
    config.autoloader = :classic

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

    # Initialize MPD client for both web and poller processes
    config.after_initialize do
      begin
        # Only initialize MPD client if the gem is available
        if defined?(MpdClient)
          Rails.logger.info "MpdClient class is available" if defined?(Rails)
          
          # Check if we should use Unix socket or TCP
          socket_path = ENV['MPD_SOCKET']
          
          if socket_path
            # Use Unix socket connection
            Rails.logger.info "Initializing MPD client with Unix socket: #{socket_path}" if defined?(Rails)
            config.mpd_client = MpdClient.new(
              nil, nil, ENV['MPD_PASSWORD'], socket_path
            )
          else
            # Use TCP connection
            host = ENV['MPD_HOST'] || 'localhost'
            port = (ENV['MPD_PORT'] || 6600).to_i
            Rails.logger.info "Initializing MPD client with TCP: #{host}:#{port}" if defined?(Rails)
            config.mpd_client = MpdClient.new(
              host, port, ENV['MPD_PASSWORD']
            )
          end
          
          # Only start polling in the poller process
          if ENV['FOREMAN_PROCESS_NAME'] == 'poller' || Rails.env.development?
            Rails.logger.info "Starting MPD client connection and polling..." if defined?(Rails)
            begin
              config.mpd_client.connect
              config.mpd_client.start_polling
              Rails.logger.info "MPD client initialized and polling started successfully" if defined?(Rails)
            rescue => e
              Rails.logger.error "Failed to start MPD client polling: #{e.message}" if defined?(Rails)
              Rails.logger.error "Error class: #{e.class}" if defined?(Rails)
              Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}" if defined?(Rails)
            end
          else
            # For web process, just connect without starting polling
            Rails.logger.info "Connecting MPD client for web process..." if defined?(Rails)
            begin
              config.mpd_client.connect
              Rails.logger.info "MPD client initialized for web process successfully" if defined?(Rails)
            rescue => e
              Rails.logger.error "Failed to connect MPD client for web process: #{e.message}" if defined?(Rails)
              Rails.logger.error "Error class: #{e.class}" if defined?(Rails)
              Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}" if defined?(Rails)
            end
          end
        else
          Rails.logger.warn "MPD client gem not available - MPD client not initialized" if defined?(Rails)
          if !defined?(MPDClient)
            Rails.logger.warn "MPDClient class not defined" if defined?(Rails)
          end
          if !defined?(MpdClient)
            Rails.logger.warn "MpdClient class not defined" if defined?(Rails)
          end
        end
      rescue => e
        Rails.logger.error "Failed to initialize MPD client: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end
  end
end
