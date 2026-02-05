# frozen_string_literal: true

module Lago
  module RedisConfig
    INSTANCES = {
      main: {
        url_env: "REDIS_URL",
        password_env: "REDIS_PASSWORD",
        sentinels_env: "REDIS_SENTINELS",
        master_name_env: "REDIS_MASTER_NAME"
      },
      cache: {
        url_env: "LAGO_REDIS_CACHE_URL",
        password_env: "LAGO_REDIS_CACHE_PASSWORD",
        sentinels_env: "LAGO_REDIS_CACHE_SENTINELS",
        master_name_env: "LAGO_REDIS_CACHE_MASTER_NAME"
      },
      store: {
        url_env: "LAGO_REDIS_STORE_URL",
        password_env: "LAGO_REDIS_STORE_PASSWORD",
        sentinels_env: "LAGO_REDIS_STORE_SENTINELS",
        master_name_env: "LAGO_REDIS_STORE_MASTER_NAME",
        db_env: "LAGO_REDIS_STORE_DB",
        ssl_env: "LAGO_REDIS_STORE_SSL",
        disable_ssl_verify_env: "LAGO_REDIS_STORE_DISABLE_SSL_VERIFY"
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
        ENV[config[:url_env]]
      end

      def configured?(instance = :main)
        config = INSTANCES.fetch(instance)
        ENV[config[:url_env]].present? || ENV[config[:sentinels_env]].present?
      end

      private

      def sentinel_mode?(config)
        ENV[config[:sentinels_env]].present?
      end

      def build_standalone_config(config)
        url = ENV[config[:url_env]]
        return {} if url.blank?

        result = {url: normalize_url(url, config)}
        add_common_options(result, config)
        result
      end

      def build_sentinel_config(config)
        sentinels = parse_sentinels(ENV[config[:sentinels_env]])
        master_name = ENV[config[:master_name_env]] || "mymaster"

        result = {
          name: master_name,
          sentinels: sentinels,
          role: :master
        }

        add_common_options(result, config)
        result
      end

      def add_common_options(result, config)
        add_password(result, config)
        add_ssl_options(result, config)
        add_db(result, config)
        add_timeouts(result)
      end

      def add_password(result, config)
        password = ENV[config[:password_env]]
        if password.present? && !password.empty?
          result[:password] = password
        end
      end

      def add_ssl_options(result, config)
        # For store instance, SSL is explicitly configured
        if config[:ssl_env]
          url = ENV[config[:url_env]]
          if ENV[config[:ssl_env]].present? || url&.start_with?("rediss:")
            result[:ssl] = true
          end

          if ENV[config[:disable_ssl_verify_env]].present?
            result[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE}
          end
        else
          # For main and cache instances, always set ssl_params for compatibility
          result[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE}
        end
      end

      def add_db(result, config)
        if config[:db_env]
          db = ENV[config[:db_env]]
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
