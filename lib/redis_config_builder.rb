# frozen_string_literal: true

require "active_support/core_ext/object/blank"

# Builds a Redis configuration hash from environment variables.
#
# Base config includes URL (REDIS_URL), SSL params, password (REDIS_PASSWORD),
# and optional Sentinel support (LAGO_REDIS_SIDEKIQ_SENTINELS, LAGO_REDIS_SIDEKIQ_MASTER_NAME).
#
# Use `with_options` to merge consumer-specific options before calling `sidekiq`.
#
# @example Sidekiq initializer
#   RedisConfigBuilder.new()
#     .with_options(pool_timeout: 5, timeout: 5)
#     .sidekiq
#
# @example ActiveJob uniqueness initializer
#   RedisConfigBuilder.new()
#     .with_options(reconnect_attempts: 4)
#     .sidekiq
class RedisConfigBuilder
  def initialize
    @extra_options = {}
  end

  def with_options(options)
    @extra_options = @extra_options.merge(options)
    self
  end

  def sidekiq
    redis_config = {
      url:,
      ssl_params: {
        verify_mode: OpenSSL::SSL::VERIFY_NONE
      }
    }.compact

    add_sentinels(redis_config)
    add_password(redis_config)

    redis_config.merge(@extra_options)
  end

  private

  attr_reader :logger

  def add_sentinels(config)
    sentinels = ENV["LAGO_REDIS_SIDEKIQ_SENTINELS"].presence
    return unless sentinels

    config[:sentinels] = parse_sentinels(sentinels)
    config[:role] = :master
    config[:name] = ENV.fetch("LAGO_REDIS_SIDEKIQ_MASTER_NAME", "master")
  end

  def url
    ENV["REDIS_URL"].presence
  end

  def add_password(config)
    password = ENV["REDIS_PASSWORD"].presence
    return unless password

    config[:password] = password
  end

  def parse_sentinels(sentinels)
    sentinels.split(",").map do |sentinel|
      host, port = sentinel.split(":")
      config = {host:}
      config[:port] = port.to_i if port.present?
      config
    end
  end
end
