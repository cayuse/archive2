require "sidekiq"

redis_url = ENV.fetch("SIDEKIQ_REDIS_URL", ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

Rails.application.config.active_job.queue_adapter = :sidekiq


