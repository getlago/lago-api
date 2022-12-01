# frozen_string_literal: true

redis_config = {
  url: ENV['REDIS_URL'],
  pool_timeout: 5,
}

if ENV['REDIS_PASSWORD'].present? && !ENV['REDIS_PASSWORD'].empty?
  redis_config = redis_config.merge({ password: ENV['REDIS_PASSWORD'] })
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end

Sidekiq.logger = Rails.logger
Sidekiq.options[:max_retries] = 0
