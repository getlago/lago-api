# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module Lago
  # Builds a Redis configuration hash from environment variables.
  #
  # Base config for `#sidekiq` includes URL (REDIS_URL), SSL params, password
  # (REDIS_PASSWORD), and optional Sentinel support
  # (LAGO_REDIS_SIDEKIQ_SENTINELS, LAGO_REDIS_SIDEKIQ_MASTER_NAME).
  #
  # Base config for `#cache` includes URL (LAGO_REDIS_CACHE_URL), SSL params,
  # password (LAGO_REDIS_CACHE_PASSWORD), and optional Sentinel support
  # (LAGO_REDIS_CACHE_SENTINELS, LAGO_REDIS_CACHE_MASTER_NAME,
  # LAGO_REDIS_CACHE_SENTINEL_PASSWORD).
  #
  # Note: only `#cache` reads a Sentinel auth password. `#sidekiq` has no
  # equivalent — LAGO_REDIS_SIDEKIQ_SENTINEL_PASSWORD is not consumed
  # today.
  #
  # Use `with_options` to merge consumer-specific options before calling
  # either method.
  #
  # @example Sidekiq initializer
  #   Lago::RedisConfigBuilder.new
  #     .with_options(pool_timeout: 5, timeout: 5)
  #     .sidekiq
  #
  # @example ActiveJob uniqueness initializer
  #   Lago::RedisConfigBuilder.new
  #     .with_options(reconnect_attempts: 4)
  #     .sidekiq
  #
  # @example Cache initializer
  #   Lago::RedisConfigBuilder.new
  #     .with_options(pool: {size: 5})
  #     .cache
  class RedisConfigBuilder
    def initialize
      @extra_options = {}
    end

    def with_options(options)
      @extra_options = extra_options.merge!(options)
      self
    end

    def sidekiq
      redis_config = {
        url: ENV["REDIS_URL"].presence,
        ssl_params: {
          verify_mode: OpenSSL::SSL::VERIFY_NONE
        }
      }.compact

      add_sentinels(
        redis_config,
        sentinels: ENV["LAGO_REDIS_SIDEKIQ_SENTINELS"].presence,
        master_name: ENV.fetch("LAGO_REDIS_SIDEKIQ_MASTER_NAME", "master").presence
      )
      add_password(redis_config, password: ENV["REDIS_PASSWORD"].presence)

      redis_config.merge(extra_options)
    end

    def cache
      redis_config = {
        url: ENV["LAGO_REDIS_CACHE_URL"].presence,
        ssl_params: {
          verify_mode: OpenSSL::SSL::VERIFY_NONE
        }
      }.compact

      add_sentinels(
        redis_config,
        sentinels: ENV["LAGO_REDIS_CACHE_SENTINELS"].presence,
        master_name: ENV.fetch("LAGO_REDIS_CACHE_MASTER_NAME", "master").presence,
        sentinel_password: ENV["LAGO_REDIS_CACHE_SENTINEL_PASSWORD"].presence
      )
      add_password(redis_config, password: ENV["LAGO_REDIS_CACHE_PASSWORD"].presence)

      redis_config.merge(extra_options)
    end

    def self.cache_enabled?
      ENV["LAGO_REDIS_CACHE_URL"].present? || ENV["LAGO_REDIS_CACHE_SENTINELS"].present?
    end

    private

    attr_reader :extra_options

    def add_sentinels(config, sentinels:, master_name:, sentinel_password: nil)
      return unless sentinels

      config[:sentinels] = parse_sentinels(sentinels)
      config[:role] = :master
      config[:name] = master_name.presence || "master"

      if sentinel_password
        config[:sentinel_password] = sentinel_password
      end
    end

    def add_password(config, password:)
      return unless password

      config[:password] = password
    end

    def parse_sentinels(sentinels)
      sentinels.split(",").map do |sentinel|
        host, port = sentinel.split(":")
        host = host&.strip
        port = port&.strip
        config = {host:}
        if port.present?
          begin
            config[:port] = Integer(port)
          rescue ArgumentError
            raise ArgumentError, "Invalid Redis sentinel port #{port.inspect} in #{sentinel.inspect}"
          end
        end
        config
      end
    end
  end
end
