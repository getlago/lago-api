# frozen_string_literal: true

module Lago
  module RedisConfig
    INSTANCES = {
      main: {
        url: "REDIS_URL",
        password: "REDIS_PASSWORD",
        sentinels: "REDIS_SENTINELS",
        master_name: "REDIS_MASTER_NAME",
        sentinel_username: "REDIS_SENTINEL_USERNAME",
        sentinel_password: "REDIS_SENTINEL_PASSWORD"
      },
      cache: {
        url: "LAGO_REDIS_CACHE_URL",
        password: "LAGO_REDIS_CACHE_PASSWORD",
        sentinels: "LAGO_REDIS_CACHE_SENTINELS",
        master_name: "LAGO_REDIS_CACHE_MASTER_NAME",
        sentinel_username: "LAGO_REDIS_CACHE_SENTINEL_USERNAME",
        sentinel_password: "LAGO_REDIS_CACHE_SENTINEL_PASSWORD",
        db: "LAGO_REDIS_CACHE_DB"
      },
      store: {
        url: "LAGO_REDIS_STORE_URL",
        password: "LAGO_REDIS_STORE_PASSWORD",
        sentinels: "LAGO_REDIS_STORE_SENTINELS",
        master_name: "LAGO_REDIS_STORE_MASTER_NAME",
        sentinel_username: "LAGO_REDIS_STORE_SENTINEL_USERNAME",
        sentinel_password: "LAGO_REDIS_STORE_SENTINEL_PASSWORD",
        db: "LAGO_REDIS_STORE_DB",
        ssl: "LAGO_REDIS_STORE_SSL",
        disable_ssl_verify: "LAGO_REDIS_STORE_DISABLE_SSL_VERIFY"
      }
    }.freeze

    class << self
      def build(instance = :main)
        config = INSTANCES.fetch(instance)

        if sentinel_mode?(config)
          build_sentinel_config(config)
        else
          build_standalone_config(config)
        end
      end

      def url(instance = :main)
        config = INSTANCES.fetch(instance)
        ENV[config[:url]]
      end

      def configured?(instance = :main)
        config = INSTANCES.fetch(instance)
        ENV[config[:url]].present? || ENV[config[:sentinels]].present?
      end

      private

      def sentinel_mode?(config)
        ENV[config[:sentinels]].present?
      end

      def build_standalone_config(config)
        url = ENV[config[:url]]
        return {} if url.blank?

        result = {url: normalize_url(url, config)}
        add_common_options(result, config)
        result
      end

      def build_sentinel_config(config)
        sentinels = parse_sentinels(ENV[config[:sentinels]])
        master_name = ENV[config[:master_name]] || "mymaster"

        result = {
          url: nil,
          name: master_name,
          sentinels: sentinels,
          role: :master
        }

        add_sentinel_auth(result, config)
        add_common_options(result, config)
        result
      end

      def add_sentinel_auth(result, config)
        sentinel_username = ENV[config[:sentinel_username]]
        sentinel_password = ENV[config[:sentinel_password]]

        if sentinel_username.present? && !sentinel_username.empty?
          result[:sentinel_username] = sentinel_username
        end

        if sentinel_password.present? && !sentinel_password.empty?
          result[:sentinel_password] = sentinel_password
        end
      end

      def add_common_options(result, config)
        add_password(result, config)
        add_ssl_options(result, config)
        add_db(result, config)
        add_timeouts(result)
      end

      def add_password(result, config)
        password = ENV[config[:password]]
        if password.present? && !password.empty?
          result[:password] = password
        end
      end

      def add_ssl_options(result, config)
        # For store instance, SSL is explicitly configured
        if config[:ssl]
          url = ENV[config[:url]]
          if ENV[config[:ssl]].present? || url&.start_with?("rediss:")
            result[:ssl] = true
          end

          if ENV[config[:disable_ssl_verify]].present?
            result[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE}
          end
        else
          # For main and cache instances, always set ssl_params for compatibility
          result[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE}
        end
      end

      def add_db(result, config)
        if config[:db]
          db = ENV[config[:db]]
          result[:db] = db.to_i if db.present?
        end
      end

      def add_timeouts(result)
        result[:timeout] = 5
        result[:reconnect_attempts] = 3
      end

      def normalize_url(url, config)
        # Store instance may not have redis:// prefix
        if config == INSTANCES[:store] && !url.start_with?("redis://", "rediss://")
          "redis://#{url}"
        else
          url
        end
      end

      def parse_sentinels(sentinels_string)
        return [] if sentinels_string.blank?

        sentinels_string.split(",").map do |sentinel|
          host, port = sentinel.strip.split(":")
          {host: host, port: (port || 26379).to_i}
        end
      end
    end
  end
end
