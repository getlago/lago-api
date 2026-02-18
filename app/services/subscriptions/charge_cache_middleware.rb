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
        fees.map do |fee|
          fee_attributes = fee.attributes
          if (pricing_unit_usage = fee.pricing_unit_usage).present?
            pricing_unit_usage_attributes = compact_hash(pricing_unit_usage.attributes, COMPACTABLE_PRICING_UNIT_USAGE_ATTRIBUTES)
            fee_attributes["pricing_unit_usage"] = pricing_unit_usage_attributes
          end
          compact_fee(fee_attributes)
        end.to_json
      end

      return fees if fees # avoid parsing the JSON if we already have the fees

      parse_cached_fees(cached_fees)
    end

    private

    attr_reader :subscription, :charge, :to_datetime, :cache

    COMPACTABLE_PROPERTIES = Set.new([
      "fixed_charges_duration",
      "fixed_charges_from_datetime",
      "fixed_charges_to_datetime"
    ]).freeze

    COMPACTABLE_ATTRIBUTES = Set.new([
      "add_on_id",
      "applied_add_on_id",
      "charge_filter_id",
      "created_at",
      "deleted_at",
      "description",
      "failed_at",
      "fixed_charge_id",
      "group_id",
      "invoice_display_name",
      "invoice_id",
      "pay_in_advance_event_id",
      "pay_in_advance_event_transaction_id",
      "pay_in_advance",
      "pricing_unit_usage",
      "refunded_at",
      "succeeded_at",
      "true_up_parent_fee_id",
      "updated_at",
      "id"
    ]).freeze

    COMPACTABLE_PRICING_UNIT_USAGE_ATTRIBUTES = Set.new([
      "id",
      "fee_id",
      "created_at",
      "updated_at"
    ]).freeze

    def parse_cached_fees(cached_fees)
      JSON.parse(cached_fees).map do |fee_attributes|
        pricing_unit_usage = fee_attributes["pricing_unit_usage"]
        pricing_unit_usage = if pricing_unit_usage.present?
          PricingUnitUsage.new(pricing_unit_usage.slice(*PricingUnitUsage.column_names))
        end

        Fee.new(**fee_attributes.slice(*Fee.column_names), pricing_unit_usage:)
      end
    end

    # This method is used to compact the fee attributes to reduce the size of the cached fees. We explicitly define
    # which attributes are compactable and which are not to avoid losing information. For instance, the `grouped_by`
    # should keep the `nil` values.
    def compact_fee(fee_attributes)
      fee_attributes = compact_hash(fee_attributes, COMPACTABLE_ATTRIBUTES)
      if (properties = fee_attributes["properties"]).present?
        fee_attributes["properties"] = compact_hash(properties, COMPACTABLE_PROPERTIES)
      end
      fee_attributes
    end

    def compact_hash(object, compactable_keys)
      object.reject { |key, value| compactable_keys.include?(key) && value.nil? }
    end

    def cache_expiration
      [(to_datetime - Time.current).to_i.seconds, 0].max
    end
  end
end
