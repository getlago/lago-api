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
      targets = subscriptions.map do |subscription|
        {
          subscription:,
          units: units_for(subscription),
          timestamp: event_timestamp_for(subscription)
        }
      end

      baselines = previous_units_by_subscription(targets)

      events_attributes = targets.filter_map do |target|
        previous_units = baselines[target[:subscription].id]
        next if previous_units && previous_units == target[:units].to_d

        {
          organization_id: target[:subscription].organization_id,
          subscription_id: target[:subscription].id,
          fixed_charge_id: fixed_charge.id,
          units: target[:units],
          timestamp: target[:timestamp]
        }
      end

      result.fixed_charge_events = ::FixedChargeEvents::BulkCreateService.call!(events_attributes:).fixed_charge_events

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
      # Incomplete (payment-gated) subscriptions receive the event with a next-period
      # timestamp even when apply_units_immediately is true: the customer paid (or is
      # paying) the gating invoice for the original units, so a change made during gating
      # must never be billed right after activation.
      if subscription
        # Emit events for active and incomplete subscriptions
        # Pending subscriptions will have events created when they activate
        (subscription.active? || subscription.incomplete?) ? [subscription] : []
      else
        fixed_charge.plan.subscriptions
          .where(status: %i[active incomplete])
          .without_fixed_charge_units_override_for(fixed_charge)
          .includes(:plan, customer: :billing_entity)
      end
    end

    def units_for(subscription)
      # Only an explicitly provided subscription can carry an override; the bulk path filters
      # overridden subscriptions out, so they always use the plan-level units.
      return fixed_charge.units unless self.subscription

      fixed_charge.effective_units_for(subscription)
    end

    def event_timestamp_for(subscription)
      if apply_units_immediately && !subscription.incomplete?
        timestamp
      else
        next_billing_period(subscription)
      end
    end

    # The baseline is the units effective at the event's own timestamp, not the units effective
    # now. A deferred change already scheduled for the next period is the baseline for another
    # deferred change, so re-setting today's value must still emit an event superseding it.
    #
    # Batch subscriptions with their individual cutoffs so anniversary billing and different
    # customer timezones do not turn the baseline lookup into one query per subscription.
    def previous_units_by_subscription(targets)
      charge_ids = [fixed_charge.id, fixed_charge.parent_id].compact

      targets.each_slice(BATCH_SIZE).each_with_object({}) do |batch, baselines|
        values = batch.map do |target|
          FixedChargeEvent.sanitize_sql_array(["(?::uuid, ?::timestamp)", target[:subscription].id, target[:timestamp]])
        end.join(", ")

        FixedChargeEvent
          .joins(<<~SQL)
            INNER JOIN (VALUES #{values}) AS targets(subscription_id, timestamp)
              ON targets.subscription_id = fixed_charge_events.subscription_id
              AND fixed_charge_events.timestamp <= targets.timestamp
          SQL
          .where(fixed_charge_id: charge_ids)
          .select("DISTINCT ON (fixed_charge_events.subscription_id) fixed_charge_events.subscription_id, units")
          .order("fixed_charge_events.subscription_id, created_at DESC")
          .each { |event| baselines[event.subscription_id] = event.units }
      end
    end

    def next_billing_period(subscription)
      ::Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true).fixed_charges_period_to_datetime + 1.second
    end
  end
end
