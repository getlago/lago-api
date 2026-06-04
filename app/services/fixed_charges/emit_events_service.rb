# frozen_string_literal: true

module FixedCharges
  class EmitEventsService < BaseService
    Result = BaseResult[:fixed_charge_events]

    def initialize(fixed_charge:, subscription: nil, apply_units_immediately: false, timestamp: Time.current.to_i)
      @fixed_charge = fixed_charge
      @subscription = subscription
      @apply_units_immediately = !!apply_units_immediately
      @timestamp = Time.zone.at(timestamp.to_i)
      super
    end

    def call
      result.fixed_charge_events = subscriptions.map do |subscription|
        ::FixedChargeEvents::CreateService.call!(
          subscription:,
          fixed_charge:,
          timestamp: apply_units_immediately ? timestamp : next_billing_period(subscription)
        ).fixed_charge_event
      end

      result
    end

    private

    attr_reader :fixed_charge, :subscription, :apply_units_immediately, :timestamp

    def subscriptions
      # When a specific subscription is provided, emit event for that subscription only
      # This handles cases like plan overrides where the subscription hasn't been updated yet
      # otherwise, emit events for all active subscriptions on the plan, except subscriptions
      # that carry a per-subscription units override for this fixed charge (their units are
      # decoupled from the plan-level value and a plan-level update must not touch them).
      if subscription
        # Emit events for active and incomplete subscriptions
        # Pending subscriptions will have events created when they activate
        (subscription.active? || subscription.incomplete?) ? [subscription] : []
      else
        fixed_charge.plan.subscriptions
          .where(status: %i[active incomplete])
          .without_fixed_charge_units_override_for(fixed_charge)
      end
    end

    def next_billing_period(subscription)
      ::Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true).fixed_charges_to_datetime + 1.second
    end
  end
end
