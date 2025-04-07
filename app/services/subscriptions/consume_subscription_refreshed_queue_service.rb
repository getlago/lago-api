# frozen_string_literal: true

module Subscriptions
  class ConsumeSubscriptionRefreshedQueueService < BaseService
    REDIS_STORE_NAME = "subscription_refreshed"
    BATCH_SIZE = 100
    PROCESSING_TIMEOUT = 1.minute

    def call
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
      @redis_client ||= Redis.new(
        url: "redis://#{ENV["LAGO_REDIS_STORE_URL"]}",
        password: ENV["LAGO_REDIS_STORE_PASSWORD"].presence,
        db: ENV["LAGO_REDIS_STORE_DB"],
        ssl: true,
        ssl_params: {
          verify_mode: OpenSSL::SSL::VERIFY_PEER
        },
        timeout: 5.0,
        reconnect_attempts: 3
      )
    end
  end
end
