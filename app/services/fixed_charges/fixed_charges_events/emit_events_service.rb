# frozen_string_literal: true

module FixedCharges
  module FixedChargesEvents
    class EmitEventsService < BaseService
      Result = BaseResult[:event]

      def initialize(fixed_charge:, subscription:, timestamp: Time.current, units: nil)
        @fixed_charge = fixed_charge
        @subscription = subscription
        @timestamp = timestamp
        @units = units || subscription.units_override_for(fixed_charge) || fixed_charge.units

        super
      end

      def call
        return result if units.zero?

        events_result = create_event(units)
        result.event = events_result.event
        result
      end

      private

      attr_reader :fixed_charge, :subscription, :timestamp, :units

      def create_event(units)
        FixedChargeEvent.create!(
          organization: subscription.organization,
          customer: subscription.customer,
          subscription:,
          code: fixed_charge.add_on.code,
          properties: {
            units: units
          }.merge(fixed_charge.default_properties),
          timestamp: timestamp
        )
      end
    end
  end
end
