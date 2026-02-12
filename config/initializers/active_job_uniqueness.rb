# frozen_string_literal: true

require "lago/redis_config_builder"

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour

  config.redlock_options = {
    retry_count: 0,
    redis_timeout: 5
  }

  redis_config = Lago::RedisConfigBuilder.new
    .with_options(reconnect_attempts: 4)
    .sidekiq

  client = if redis_config.key?(:sentinels)
    RedisClient.sentinel(**redis_config).new_client
  else
    RedisClient.new(**redis_config)
  end

  config.redlock_servers = [client]
end
