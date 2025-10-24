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
        fees = yield
        next [] if fees.all? { |fee| fee.amount_cents.zero? }

        fees
          .map { |fee| deep_hash_compact(fee.attributes.merge("pricing_unit_usage" => fee.pricing_unit_usage&.attributes)) }
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

    def deep_hash_compact(hash)
      hash.compact.transform_values do |value|
        if value.is_a?(Hash)
          deep_hash_compact(value)
        elsif value.is_a?(Array)
          value.each { |v| deep_hash_compact(v) }
        else
          value
        end
      end
    end

    def cache_expiration
      [(to_datetime - Time.current).to_i.seconds, 0].max
    end
  end
end
