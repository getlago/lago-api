# frozen_string_literal: true

module Subscriptions
  class ChargeCacheMiddleware
    EMPTY_ARRAY = [].freeze
    PRICING_UNIT_USAGE_COLUMNS = PricingUnitUsage.column_names.freeze
    PRESENTATION_BREAKDOWN_COLUMNS = PresentationBreakdown.column_names.freeze

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
                presentation_breakdown.attributes.slice(*PRESENTATION_BREAKDOWN_COLUMNS)
              end
            )
          end
          .to_json
      end

      cached_fees = JSON.parse(json)

      cached_fees.map do |fee_attributes|
        pricing_unit_usage = if fee_attributes["pricing_unit_usage"].present?
          PricingUnitUsage.instantiate(fee_attributes["pricing_unit_usage"].slice(*PRICING_UNIT_USAGE_COLUMNS))
        end
        pricing_unit_usage&.instance_variable_set(:@new_record, true)

        # Use instantiate (DB hydration path) instead of new (user-input path) to avoid
        # _default_attributes.deep_dup + write_from_user overhead per attribute — ~42x faster for Fee.
        fee = Fee.instantiate(fee_attributes.except("pricing_unit_usage", "presentation_breakdowns"))
        # Reset @new_record so in-memory associations
        fee.instance_variable_set(:@new_record, true)

        fee.association(:pricing_unit_usage).target = pricing_unit_usage
        fee.association(:pricing_unit_usage).loaded!

        presentation_breakdowns = (fee_attributes["presentation_breakdowns"] || EMPTY_ARRAY).map do |breakdown_attributes|
          presentation_breakdown = PresentationBreakdown.instantiate(breakdown_attributes.slice(*PRESENTATION_BREAKDOWN_COLUMNS))
          presentation_breakdown.instance_variable_set(:@new_record, true)
          presentation_breakdown.association(:organization).target = subscription.organization
          presentation_breakdown.association(:organization).loaded!
          presentation_breakdown
        end

        fee.association(:presentation_breakdowns).target.replace(presentation_breakdowns)
        fee.association(:presentation_breakdowns).loaded!

        fee
      end
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache

    def cache_expiration
      return 0 unless to_datetime

      [(to_datetime - Time.current).to_i.seconds, 0].max
    end
  end
end
