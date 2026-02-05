# frozen_string_literal: true

module Subscriptions
  class ConsumeSubscriptionRefreshedQueueService < BaseService
    REDIS_STORE_NAME = "subscription_refreshed"
    BATCH_SIZE = 100
    PROCESSING_TIMEOUT = 1.minute

    # In events-processor, cache is set to expire 5 seconds after the start of the processing
    # to give time to Clickhouse to fully merge the new event.
    # On API, the subscription refresh is processed by a clock every 1 minute, but we have to make sure that the cache
    # is fully expired before computing the new usage.
    # To handle the worst case scenario, we are adding 5 more seconds before processing the subscription.
    REFRESH_WAIT_TIME = 5.seconds

    def call
      return result unless Lago::RedisConfig.configured?(:store)

      start_time = Time.current

      loop do
        if Time.current - start_time > PROCESSING_TIMEOUT
          # Avoid looping for ever if the producer is quicker than this consumer
          break
        end

        values = redis_client.srandmember(REDIS_STORE_NAME, BATCH_SIZE)
        break if values.blank?

        values.each do |value|
          Subscriptions::FlagRefreshedJob.set(wait: REFRESH_WAIT_TIME).perform_later(value.split(":").last)
        end

        redis_client.srem(REDIS_STORE_NAME, values) if values.present?
      end

      result
    end

    private

    def redis_client
      return @redis_client if defined? @redis_client

      @redis_client ||= Redis.new(Lago::RedisConfig.build(:store))
    end
  end
end
