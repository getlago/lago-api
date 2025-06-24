# frozen_string_literal: true

module FixedCharges
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
      Events::CreateService.call!(
        organization: subscription.organization,
        params: {
          code: fixed_charge.add_on.code,
          transaction_id: "#{timestamp.strftime('%d-%m-%Y')}/#{fixed_charge.id}/#{subscription.id}/#{SecureRandom.hex(4)}",
          external_subscription_id: subscription.external_id,
          properties: {
            units: units
          },
          source: Event.sources[:fixed_charge]
        },
        timestamp: timestamp,
        metadata: {
          fixed_charge_id: fixed_charge.id,
          subscription_id: subscription.id
        }
      )
    end
  end
end
