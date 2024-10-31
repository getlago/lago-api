# frozen_string_literal: true

module Subscriptions
  class ChargeCacheMiddleware
    def initialize(subscription:, charge:, to_datetime:, cache: true)
      @subscription = subscription
      @charge = charge
      @to_datetime = to_datetime
      @cache = cache
    end

    def call(charge_filter:)
      return yield unless cache

      json = Subscriptions::ChargeCacheService.call(subscription:, charge:, charge_filter:, expires_in: cache_expiration) do
        yield.to_json
      end

      JSON.parse(json).map { |j| Fee.new(j.slice(*Fee.column_names)) }
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache

    def cache_expiration
      (to_datetime - Time.current).to_i.seconds
    end
  end
end
