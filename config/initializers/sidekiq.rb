# frozen_string_literal: true

redis_config = {
  url: ENV['REDIS_URL'],
  password: ENV['REDIS_PASSWORD'],
  pool_timeout: 5,
}

redis_config = redis_config.merge({ password: ENV['REDIS_PASSWORD'] }) if ENV['REDIS_PASSWORD'].present?

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end

Sidekiq.logger = Rails.logger
Sidekiq.options[:max_retries] = 0
