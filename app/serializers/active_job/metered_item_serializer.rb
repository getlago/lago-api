# frozen_string_literal: true

module ActiveJob
  class MeteredItemSerializer < ActiveJob::Serializers::ObjectSerializer
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
          "boundaries" => metered_item.boundaries.to_h,
          "charge_filter" => source.charge_filter,
          "properties_override" => source.properties_override
        }
      elsif source.is_a?(Fees::ChargeService::Sources::BillingSegment)
        {
          "source_type" => "billing_segment",
          "billing_segment" => source.billing_segment.attributes.except("id", "created_at", "updated_at"),
          "product_filter" => source.product_filter
        }
      else
        raise ArgumentError, "Unsupported MeteredItem source: #{source.class}"
      end

      serialized_payload = ActiveJob::Arguments.serialize([payload.merge("event" => metered_item.event&.as_json)]).first
      super(serialized_payload)
    end

    def deserialize(payload)
      payload = ActiveJob::Arguments.deserialize([payload.except("_aj_serialized")]).first
      event = payload["event"] && Events::CommonFactory.new_instance(source: payload["event"])

      case payload["source_type"]
      when "billing_segment"
        Fees::ChargeService::MeteredItem.from_billing_segment(
          billing_segment: BillingSegment.new(payload.fetch("billing_segment")),
          product_filter: payload["product_filter"],
          event:
        )
      when "charge"
        Fees::ChargeService::MeteredItem.from_charge(
          charge: payload["charge"],
          boundaries: BillingPeriodBoundaries.new(**payload["boundaries"].symbolize_keys),
          charge_filter: payload["charge_filter"],
          properties: payload["properties_override"],
          event:
        )
      else
        raise ArgumentError, "Unsupported MeteredItem source type: #{payload["source_type"].inspect}"
      end
    end
  end
end
