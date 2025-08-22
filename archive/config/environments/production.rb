require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # SSL behavior is configurable for testing vs. production
  config.assume_ssl = ENV.fetch("ASSUME_SSL", "false") == "true"
  config.force_ssl  = ENV.fetch("FORCE_SSL",  "false") == "true"

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Background jobs: use Sidekiq when enabled, otherwise run inline (synchronous)
  use_sidekiq = ENV.fetch("USE_SIDEKIQ", "false") == "true"
  config.active_job.queue_adapter = use_sidekiq ? :sidekiq : :inline

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host and protocol used in generated URLs (mailer, Active Storage, etc.)
  app_host = ENV.fetch("APP_HOST", "musicarchive.com")
  app_proto = ENV.fetch("APP_PROTOCOL", config.force_ssl || config.assume_ssl ? "https" : "http")
  config.action_mailer.default_url_options = { host: app_host, protocol: app_proto }
  
  # Set default URL options for Active Storage
  config.active_storage.default_url_options = { host: app_host, protocol: app_proto }

  # Configure email delivery for production using AWS SES SMTP
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  # AWS SES SMTP configuration
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("AWS_SES_SMTP_HOST", "email-smtp.us-east-2.amazonaws.com"),
    port: ENV.fetch("AWS_SES_SMTP_PORT", "587").to_i,
    domain: ENV.fetch("AWS_SES_SMTP_DOMAIN", "cavaforge.net"),
    user_name: ENV.fetch("AWS_SES_SMTP_USERNAME", "dummy_username_for_build"),
    password: ENV.fetch("AWS_SES_SMTP_PASSWORD", "dummy_password_for_build"),
    authentication: :login,
    enable_starttls_auto: true
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Host authorization: allow all hosts when explicitly enabled for testing
  if ENV.fetch("ALLOW_ALL_HOSTS", "false") == "true"
    config.hosts.clear
  else
    # Allow configured host and common local hosts
    config.hosts << app_host rescue nil
    config.hosts << "localhost"
    config.hosts << "127.0.0.1"
  end

  # CSRF origin check: can be disabled for IP/HTTP testing (not recommended long-term)
  config.action_controller.forgery_protection_origin_check = ENV.fetch("FORGERY_ORIGIN_CHECK", "true") == "true"
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
