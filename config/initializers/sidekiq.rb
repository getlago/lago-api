# frozen_string_literal: true

redis_config = {
  url: ENV['REDIS_URL'],
  pool_timeout: 5,
  ssl_params: {
    verify_mode: OpenSSL::SSL::VERIFY_NONE,
  },
}

if ENV['REDIS_PASSWORD'].present? && !ENV['REDIS_PASSWORD'].empty?
  redis_config = redis_config.merge({ password: ENV['REDIS_PASSWORD'] })
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
  config.logger = Rails.logger
  config[:max_retries] = 0
  config[:dead_max_jobs] = 100_000
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
  config.logger = Rails.logger
end
