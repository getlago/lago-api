# frozen_string_literal: true

module FixedCharges
  class EmitEventsForActiveSubscriptionsService < BaseService
    def initialize(fixed_charge:)
      @fixed_charge = fixed_charge
      super
    end

    def call
      fixed_charge.plan.subscriptions.active.find_each do |subscription|
        FixedCharges::EmitFixedChargeEventService.call!(
          subscription:,
          fixed_charge:
        )
      end

      result
    end

    private

    attr_reader :fixed_charge
  end
end
