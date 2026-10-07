# frozen_string_literal: true

module X402
  class ReservationCounter
    TTL = 1.hour

    class UnavailableError < StandardError; end

    UNAVAILABLE_ERRORS = [UnavailableError, ::Redis::BaseError, ::ConnectionPool::Error, ::ConnectionPool::TimeoutError].freeze

    def self.enabled?(organization)
      !organization.feature_flag_enabled?(:x402_reservation_counter_disabled)
    end

    def initialize(wallet)
      @wallet = wallet
    end

    def reserve(amount_cents)
      replies = redis.then do |client|
        client.pipelined do |pipeline|
          pipeline.incrby(key, amount_cents)
          pipeline.expire(key, TTL.to_i)
        end
      end

      replies.first
    rescue *UNAVAILABLE_ERRORS => e
      report(e)
      nil
    end

    def capture
      Rails.cache.read(key, raw: true).to_i
    end

    def release(amount_cents)
      Rails.cache.decrement(key, amount_cents, expires_in: TTL)
    end

    private

    attr_reader :wallet

    def key
      "x402:reserved:#{wallet.id}"
    end

    def redis
      if Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
        Rails.cache.redis
      else
        raise UnavailableError, "the cache store is not Redis"
      end
    end

    def report(error)
      Rails.logger.warn("[x402] reservation counter unavailable wallet_id=#{wallet.id}: #{error.class} #{error.message}")
      Sentry.capture_exception(error, extra: {organization_id: wallet.organization_id, wallet_id: wallet.id})
    end
  end
end
