# Controls whether audio processing runs inline (synchronously) or via Sidekiq.
# Default to inline for more deterministic imports; override with env.
Rails.application.configure do
  config.x.inline_audio_processing = ENV.fetch("INLINE_AUDIO_PROCESSING", "true") == "true"
end


