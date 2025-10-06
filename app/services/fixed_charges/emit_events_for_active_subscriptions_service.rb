# frozen_string_literal: true

module FixedCharges
  class EmitEventsForActiveSubscriptionsService < BaseService
    def initialize(fixed_charge:, subscription: nil)
      @fixed_charge = fixed_charge
      @subscription = subscription
      super
    end

    def call
      if subscription
        # When a specific subscription is provided, emit event for that subscription only
        # This handles cases like plan overrides where the subscription hasn't been updated yet
        FixedChargeEvents::CreateService.call!(
          subscription:,
          fixed_charge:
        )
      else
        # Default behavior: emit events for all active subscriptions on the plan
        fixed_charge.plan.subscriptions.active.find_each do |subscription|
          FixedChargeEvents::CreateService.call!(
            subscription:,
            fixed_charge:
          )
        end
      end

      result
    end

    private

    attr_reader :fixed_charge, :subscription
  end
end
