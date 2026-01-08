# frozen_string_literal: true

require "flipper/adapters/redis"

Flipper.configure do |config|
  config.adapter do
    Flipper::Adapters::Redis.new(
      Redis.new({
        url: ENV["LAGO_REDIS_FEATURE_FLAGS_URL"] || ENV["REDIS_URL"],
        password: ENV["LAGO_REDIS_FEATURE_FLAGS_PASSWORD"] || ENV["REDIS_PASSWORD"]
      }),
      key_prefix: "flipper:"
    )
  end
end
