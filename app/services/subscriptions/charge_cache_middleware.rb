# frozen_string_literal: true

module Subscriptions
  class ChargeCacheMiddleware
    include BuildFastActiveRecord

    EMPTY_ARRAY = [].freeze

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
          .map do |fee|
            fee.attributes.merge(
              "pricing_unit_usage" => fee.pricing_unit_usage&.attributes,
              "presentation_breakdowns" => fee.presentation_breakdowns.map do |presentation_breakdown|
                presentation_breakdown.attributes.slice(*presentation_breakdown_columns)
              end
            )
          end
          .to_json
      end

      cached_fees = JSON.parse(json)

      cached_fees.map do |fee_attributes|
        pricing_unit_usage = if fee_attributes["pricing_unit_usage"].present?
          build_fast_record(PricingUnitUsage, fee_attributes["pricing_unit_usage"].slice(*pricing_unit_usage_columns), fee_attributes["pricing_unit_usage"]["id"].blank?)
        end

        fee = build_fast_record(Fee, fee_attributes.slice(*fee_columns), fee_attributes["id"].blank?)

        presentation_breakdowns = (fee_attributes["presentation_breakdowns"] || EMPTY_ARRAY).map do |breakdown_attributes|
          presentation_breakdown = build_fast_record(PresentationBreakdown, breakdown_attributes.slice(*presentation_breakdown_columns), breakdown_attributes["id"].blank?)
          presentation_breakdown.association(:organization).target = subscription.organization
          presentation_breakdown.association(:fee).target = fee
          presentation_breakdown
        end

        fee.association(:pricing_unit_usage).target = pricing_unit_usage
        fee.association(:presentation_breakdowns).target = presentation_breakdowns
        fee.association(:charge).target = charge
        fee
      end
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache

    def cache_expiration
      return 0 unless to_datetime

      [(to_datetime - Time.current).to_i.seconds, 0].max
    end

    def pricing_unit_usage_columns
      @pricing_unit_usage_columns ||= PricingUnitUsage.column_names.freeze
    end

    def presentation_breakdown_columns
      @presentation_breakdown_columns ||= PresentationBreakdown.column_names.freeze
    end

    def fee_columns
      @fee_columns ||= Fee.column_names.freeze
    end
  end
end
