# frozen_string_literal: true

module FixedCharges
  class EmitEventsForActiveSubscriptionsService < BaseService
    def initialize(fixed_charge:, subscription: nil, apply_units_immediately: false, timestamp: Time.current)
      @fixed_charge = fixed_charge
      @subscription = subscription
      @apply_units_immediately = !!apply_units_immediately
      @timestamp = timestamp
      super
    end

    def call
      subscriptions.each do |subscription|
        ::FixedChargeEvents::CreateService.call!(
          subscription:,
          fixed_charge:,
          timestamp: apply_units_immediately ? timestamp : next_billing_period(subscription)
        )
      end

      result
    end

    private

    attr_reader :fixed_charge, :subscription, :apply_units_immediately, :timestamp

    def subscriptions
      # When a specific subscription is provided, emit event for that subscription only
      # This handles cases like plan overrides where the subscription hasn't been updated yet
      # otherwise, emit events for all active subscriptions on the plan
      if subscription
        [subscription]
      else
        fixed_charge.plan.subscriptions.active
      end
    end

    def next_billing_period(subscription)
      ::Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true).fixed_charges_to_datetime + 1.second
    end
  end
end
