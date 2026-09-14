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
      events_attributes = if subscription
        subscription_event_attributes
      else
        subscriptions.map { |subscription| event_attributes(subscription) }
      end
      result.fixed_charge_events = ::FixedChargeEvents::BulkCreateService.call!(events_attributes:).fixed_charge_events

      result
    end

    private

    attr_reader :fixed_charge, :subscription, :apply_units_immediately, :timestamp

    # Deduplicate individual subscription updates; keep plan-wide emission unchanged.
    def subscription_event_attributes
      return [] unless subscription.active? || subscription.incomplete?

      attributes = event_attributes(subscription)
      if units_unchanged?(attributes)
        []
      else
        [attributes]
      end
    end

    def subscriptions
      fixed_charge.plan.subscriptions
        .where(status: %i[active incomplete])
        .without_fixed_charge_units_override_for(fixed_charge)
        .includes(:plan, customer: :billing_entity)
    end

    def event_attributes(subscription)
      {
        organization_id: subscription.organization_id,
        subscription_id: subscription.id,
        fixed_charge_id: fixed_charge.id,
        units: units_for(subscription),
        timestamp: event_timestamp_for(subscription)
      }
    end

    def units_for(subscription)
      # Plan-wide updates exclude subscriptions with their own units override.
      return fixed_charge.units unless self.subscription

      fixed_charge.effective_units_for(subscription)
    end

    def event_timestamp_for(subscription)
      # Incomplete subscriptions must keep the units used by their activation invoice.
      if apply_units_immediately && !subscription.incomplete?
        timestamp
      else
        next_billing_period(subscription)
      end
    end

    # Compare at the event's timestamp so deferred changes can supersede scheduled units.
    def units_unchanged?(attributes)
      previous_units = FixedChargeEvent
        .where(subscription:, fixed_charge_id: [fixed_charge.id, fixed_charge.parent_id].compact)
        .where(timestamp: ..attributes[:timestamp])
        .order(created_at: :desc)
        .pick(:units)

      previous_units == attributes[:units].to_d
    end

    def next_billing_period(subscription)
      ::Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true).fixed_charges_period_to_datetime + 1.second
    end
  end
end
