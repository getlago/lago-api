# frozen_string_literal: true

module ActiveJob
  module Serializers
    class MeteredItemSerializer < ObjectSerializer
      def self.serialize?(argument)
        argument.is_a?(Fees::ChargeService::MeteredItem) && [
          Fees::ChargeService::Sources::Charge,
          Fees::ChargeService::Sources::BillingSegment
        ].any? { |source_class| argument.source.is_a?(source_class) }
      end

      def serialize(metered_item)
        source = metered_item.source
        payload = if source.is_a?(Fees::ChargeService::Sources::Charge)
          {
            "source_type" => "charge",
            "charge" => source.charge,
            "boundaries" => source.boundaries.to_h,
            "charge_filter" => source.charge_filter,
            "properties_override" => source.properties_override
          }
        elsif source.is_a?(Fees::ChargeService::Sources::BillingSegment)
          {
            "source_type" => "billing_segment",
            "billing_segment" => source.billing_segment,
            "product_filter" => source.product_filter
          }
        else
          raise ArgumentError, "Unsupported MeteredItem source: #{source.class}"
        end

        super(payload.merge("event" => metered_item.event&.as_json))
      end

      def deserialize(payload)
        event = payload["event"] && Events::CommonFactory.new_instance(source: payload["event"])

        if payload["source_type"] == "billing_segment"
          Fees::ChargeService::MeteredItem.from_billing_segment(payload["billing_segment"], event:)
        else
          Fees::ChargeService::MeteredItem.from_charge(
            charge: payload["charge"],
            boundaries: BillingPeriodBoundaries.new(**payload["boundaries"].symbolize_keys),
            charge_filter: payload["charge_filter"],
            properties: payload["properties_override"],
            event:
          )
        end
      end
    end
  end
end
