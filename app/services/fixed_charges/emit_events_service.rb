# frozen_string_literal: true

module FixedCharges
  class EmitEventsService < BaseService
    def initialize(fixed_charge:, subscription:, timestamp: Time.current, units: nil)
      @fixed_charge = fixed_charge
      @subscription = subscription
      @timestamp = timestamp
      @units = units || subscription.units_override_for(fixed_charge) || fixed_charge.units
    end

    def call
      return if units.zero?

      create_event(units)
    end

    private

    attr_reader :fixed_charge, :subscription, :timestamp, :units

    def create_event(units)
      Events::CreateService.call(
        organization: subscription.organization,
        params: {
          code: fixed_charge.code,
          transaction_id: "#{strftime(timestamp)}/#{fixed_charge.id}/#{subscription.id}",
          external_subscription_id: subscription.external_id,
          properties: {
            units: units
          },
          timestamp: timestamp,
          source: Event.sources[:fixed_charge]
        }
      )
    end
  end
end
