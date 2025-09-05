# frozen_string_literal: true

module FixedCharges
  class EmitFixedChargeEventService < BaseService
    Result = BaseResult[:fixed_charge_event]

    def initialize(subscription:, fixed_charge:, timestamp: Time.current)
      @subscription = subscription
      @fixed_charge = fixed_charge
      @timestamp = timestamp
      super
    end

    def call
      create_event_result = FixedChargeEvents::CreateService.call(
        subscription:,
        fixed_charge:,
        timestamp:
      )

      return create_event_result if create_event_result.failure?

      result.fixed_charge_event = create_event_result.fixed_charge_event
      result
    end

    private

    attr_reader :subscription, :fixed_charge, :timestamp
  end
end
