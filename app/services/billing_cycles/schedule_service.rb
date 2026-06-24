# frozen_string_literal: true

module BillingCycles
  # Outbox step for one subscription product item: for every billing boundary that is
  # due (next_billing_at <= up_to), atomically write a pending billing_cycle and
  # advance the clock. The loop catches a behind clock up one period at a time, so a
  # subscription that missed ticks emits one cycle per missed period — never skipped,
  # never double-billed (the unique (product item, period_from) index is the backstop,
  # and the advisory lock serialises concurrent runs for the same item).
  #
  # The scheduler resolves the rate only for its interval/timing (to compute the next
  # boundary); the processor re-resolves at period_from to price.
  class ScheduleService < BaseService
    Result = BaseResult[:billing_cycles]

    def initialize(subscription_product_item:, up_to: Time.current)
      @subscription_product_item = subscription_product_item
      @up_to = up_to
      super
    end

    def call
      result.billing_cycles = []

      subscription_product_item.with_advisory_lock("billing_cycle_schedule_#{subscription_product_item.id}") do
        schedule_due_cycles
      end

      result
    end

    private

    attr_reader :subscription_product_item, :up_to

    def schedule_due_cycles
      while subscription_product_item.next_billing_at <= up_to
        rate = resolve_rate
        # Can't compute the next boundary without an interval; leave the clock for a
        # later retry once the catalog is fixed rather than skipping the period.
        break unless rate

        dates = BillingPeriods::DatesService.from_subscription_product_item(
          subscription_product_item, rate:, billing_at: subscription_product_item.next_billing_at
        )

        ActiveRecord::Base.transaction do
          result.billing_cycles << BillingCycle.create!(
            organization: subscription_product_item.organization,
            subscription: subscription_product_item.subscription,
            subscription_product_item:,
            billing_at: subscription_product_item.next_billing_at,
            # Clamp to the subscription start so a mid-cycle start bills only the
            # remainder (e.g. [Feb 15, Feb 28], not the whole month). No-op on every
            # period after the first, where started_at precedes the boundary.
            period_from: [dates.period_from, started_at_floor].max,
            period_to: dates.period_to
          )

          subscription_product_item.update!(next_billing_at: dates.next_billing_at)
        end
      end
    end

    def started_at_floor
      @started_at_floor ||= subscription_product_item.started_at
        .in_time_zone(subscription_product_item.subscription.customer.applicable_timezone)
        .beginning_of_day
        .utc
    end

    def resolve_rate
      SubscriptionProductItems::ResolveRateService
        .call(subscription_product_item:, datetime: subscription_product_item.next_billing_at)
        .rate
    end
  end
end
