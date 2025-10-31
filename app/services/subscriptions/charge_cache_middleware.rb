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

      fees = nil
      cached_fees = Subscriptions::ChargeCacheService.call(subscription:, charge:, charge_filter:, expires_in: cache_expiration) do
        fees = yield
        fees.map { |fee| fee.attributes.merge("pricing_unit_usage" => fee.pricing_unit_usage&.attributes) }
          .then { |fees| deep_compact(fees) }
          .to_json
      end

      return fees if fees # avoid parsing the JSON if we already have the fees

      parse_cached_fees(cached_fees)
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache

    def parse_cached_fees(cached_fees)
      JSON.parse(cached_fees).map do |fee_attributes|
        pricing_unit_usage = fee_attributes["pricing_unit_usage"]
        pricing_unit_usage = if pricing_unit_usage.present?
          PricingUnitUsage.new(pricing_unit_usage.slice(*PricingUnitUsage.column_names))
        end

        Fee.new(**fee_attributes.slice(*Fee.column_names), pricing_unit_usage:)
      end
    end

    def deep_compact(object)
      if object.is_a?(Hash)
        object.compact.transform_values { |v| deep_compact(v) }
      elsif object.is_a?(Array)
        object.map { |v| deep_compact(v) }
      else
        object
      end
    end

    def cache_expiration
      [(to_datetime - Time.current).to_i.seconds, 0].max
    end
  end
end
