# frozen_string_literal: true

require "lago/redis_config"

ActiveJob::Uniqueness.configure do |config|
  config.lock_ttl = 1.hour

  config.redlock_options = {
    retry_count: 0,
    redis_timeout: 5
  }

  redis_config = Lago::RedisConfig.build(:main).merge(reconnect_attempts: 4)

  config.redlock_servers = [
    RedisClient.new(redis_config)
  ]
end
