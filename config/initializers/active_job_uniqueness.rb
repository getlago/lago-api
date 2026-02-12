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

  # `active_job_uniqueness` uses `redlock-rb` under the hood, which only supports `redis-client` gem which uses a
  # different configuration than `redis` gem used by Sidekiq.
  client = Redis.new(redis_config)._client

  config.redlock_servers = [client]
end
