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
        yield
          .map { |fee| fee.attributes.merge("pricing_unit_usage" => fee.pricing_unit_usage&.attributes) }
          .to_json
      end

      JSON.parse(json).map do |j|
        pricing_unit_usage = if j["pricing_unit_usage"].present?
          PricingUnitUsage.new(j["pricing_unit_usage"].slice(*PricingUnitUsage.column_names))
        end

        Fee.new(
          **j.slice(*Fee.column_names),
          pricing_unit_usage:
        )
      end
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache

    def cache_expiration
      [(to_datetime - Time.current).to_i.seconds, 0].max
    end
  end
end
