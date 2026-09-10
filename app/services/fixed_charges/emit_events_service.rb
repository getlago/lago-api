# frozen_string_literal: true

module FixedCharges
  class EmitEventsService < BaseService
    Result = BaseResult[:fixed_charge_events]

    BATCH_SIZE = 1_000

    def initialize(fixed_charge:, subscription: nil, apply_units_immediately: false, timestamp: Time.current.to_i)
      @fixed_charge = fixed_charge
      @subscription = subscription
      @apply_units_immediately = !!apply_units_immediately
      @timestamp = Time.zone.at(timestamp.to_i)
      super
    end

    def call
      events_attributes = subscription_batches.flat_map { |batch| changed_event_attributes(batch) }
      result.fixed_charge_events = ::FixedChargeEvents::BulkCreateService.call!(events_attributes:).fixed_charge_events

      result
    end

    private

    attr_reader :fixed_charge, :subscription, :apply_units_immediately, :timestamp

    # Plan updates can affect thousands of subscriptions; load prior units once per batch.
    def subscription_batches
      if subscription
        subscriptions.each_slice(BATCH_SIZE)
      else
        subscriptions.find_in_batches(batch_size: BATCH_SIZE)
      end
    end

    def subscriptions
      if subscription
        # During a plan override, the supplied subscription may still belong to the original plan.
        (subscription.active? || subscription.incomplete?) ? [subscription] : []
      else
        fixed_charge.plan.subscriptions
          .where(status: %i[active incomplete])
          .without_fixed_charge_units_override_for(fixed_charge)
          .includes(:plan, customer: :billing_entity)
      end
    end

    def changed_event_attributes(batch)
      attributes = batch.map { |subscription| event_attributes(subscription) }
      previous_units = previous_units_by_subscription(attributes)

      attributes.reject { |attrs| previous_units[attrs[:subscription_id]] == attrs[:units].to_d }
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

    # Use each event's timestamp so deferred changes can supersede previously scheduled units.
    def previous_units_by_subscription(attributes)
      scope = FixedChargeEvent.where(fixed_charge_id: [fixed_charge.id, fixed_charge.parent_id].compact)
      events = attributes.group_by { |attrs| attrs[:timestamp] }.map do |timestamp, group|
        scope.where(subscription_id: group.pluck(:subscription_id), timestamp: ..timestamp)
      end.reduce(:or)

      events.select("DISTINCT ON (subscription_id) subscription_id, units")
        .order(:subscription_id, created_at: :desc)
        .to_h { |event| [event.subscription_id, event.units] }
    end

    def next_billing_period(subscription)
      ::Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true).fixed_charges_period_to_datetime + 1.second
    end
  end
end
