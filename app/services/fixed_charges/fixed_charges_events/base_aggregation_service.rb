# frozen_string_literal: true

module FixedCharges
  module FixedChargesEvents
    class BaseAggregationService < BaseService
      def initialize(fixed_charge:, subscription:, boundaries:)
        @fixed_charge = fixed_charge
        @subscription = subscription
        @boundaries = OpenStruct.new(boundaries)
        @fixed_charge_events = fixed_charge_events_scope
        @customer = subscription.customer

        super
      end

      def fixed_charge_events_scope
        FixedChargeEvent.where(
          organization: subscription.organization,
          subscription:,
          code: fixed_charge.add_on.code
        ).where(
          "timestamp >= ? AND timestamp <= ?",
          from_datetime,
          to_datetime
        ).order(:timestamp)
      end

      # private

      attr_reader :fixed_charge, :subscription, :boundaries, :fixed_charge_events, :customer

      def from_datetime
        boundaries[:from_datetime]
      end

      def to_datetime
        boundaries[:to_datetime]
      end

      def charges_duration
        boundaries[:charges_duration]
      end
    end
  end
end