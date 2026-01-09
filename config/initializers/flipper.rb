# frozen_string_literal: true

require "flipper/adapters/redis"

Flipper.configure do |config|
  config.adapter do
    redis_config = {
      url: ENV["LAGO_REDIS_FEATURE_FLAGS_URL"] || ENV["REDIS_URL"]
    }
    password = ENV["LAGO_REDIS_FEATURE_FLAGS_PASSWORD"].presence || ENV["REDIS_PASSWORD"].presence
    redis_config[:password] = password if password

    Flipper::Adapters::Redis.new(
      Redis.new(redis_config),
      key_prefix: "flipper:"
    )
  end
end
