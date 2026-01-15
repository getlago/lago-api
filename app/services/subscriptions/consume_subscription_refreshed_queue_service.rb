# frozen_string_literal: true

module Subscriptions
  class ConsumeSubscriptionRefreshedQueueService < BaseService
    REDIS_STORE_NAME = "subscription_refreshed"
    BATCH_SIZE = 100
    PROCESSING_TIMEOUT = 1.minute

    def call
      return result if ENV["LAGO_REDIS_STORE_URL"].blank?

      start_time = Time.current

      loop do
        if Time.current - start_time > PROCESSING_TIMEOUT
          # Avoid looping for ever if the producer is quicker than this consumer
          break
        end

        values = redis_client.srandmember(REDIS_STORE_NAME, BATCH_SIZE)
        break if values.blank?

        values.each { |v| Subscriptions::FlagRefreshedJob.perform_later(v.split(":").last) }

        redis_client.srem(REDIS_STORE_NAME, values) if values.present?
      end

      result
    end

    private

    def redis_client
      return @redis_client if defined? @redis_client

      url = if ENV["LAGO_REDIS_STORE_URL"].start_with?("redis://")
        ENV["LAGO_REDIS_STORE_URL"]
      else
        "redis://#{ENV["LAGO_REDIS_STORE_URL"]}"
      end

      config = {
        url:,
        ssl_params: {
          verify_mode: OpenSSL::SSL::VERIFY_NONE
        },
        timeout: 5.0,
        reconnect_attempts: 3
      }

      config[:password] = ENV["LAGO_REDIS_STORE_PASSWORD"] if ENV["LAGO_REDIS_STORE_PASSWORD"].present?
      config[:db] = ENV["LAGO_REDIS_STORE_DB"] if ENV["LAGO_REDIS_STORE_DB"].present?

      if ENV["LAGO_REDIS_STORE_SSL"].present? || ENV["LAGO_REDIS_STORE_URL"].start_with?(/rediss?:/)
        config[:ssl] = true
      end

      @redis_client ||= Redis.new(config)
    end
  end
end
