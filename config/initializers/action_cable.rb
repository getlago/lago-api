# frozen_string_literal: true

# Configure ActionCable to use Redis with optional Sentinel support
# This overrides the cable.yml configuration when Redis is configured

Rails.application.configure do
  next unless Lago::RedisConfig.configured?(:main)

  redis_config = Lago::RedisConfig.build(:main)
  next if redis_config.empty?

  channel_prefix = "lago_#{Rails.env}"

  config.action_cable.cable = redis_config.merge(
    adapter: "redis",
    channel_prefix: channel_prefix
  )
end
