# frozen_string_literal: true

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

redis_client = RedisClient.new(redis_config)
Rails.application.config.lock_manager = Redlock::Client.new([redis_client])
