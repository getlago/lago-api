# frozen_string_literal: true

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour

  config.redlock_options = {
    retry_count: 0,
    redis_timeout: 5
  }

  redis_config = {
    url: ENV["REDIS_URL"],
    ssl_params: {
      verify_mode: OpenSSL::SSL::VERIFY_NONE
    },
    reconnect_attempts: 4
  }

  if ENV["REDIS_PASSWORD"].present? && !ENV["REDIS_PASSWORD"].empty?
    redis_config = redis_config.merge({password: ENV["REDIS_PASSWORD"]})
  end

  config.redlock_servers = [
    RedisClient.new(redis_config)
  ]
end
