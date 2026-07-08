# frozen_string_literal: true

module BillingCycles
  # Producer lane, scoped to ONE customer. For every due product item (next_billing_at
  # <= up_to) it writes a billing_cycle and advances that item's clock — catching a
  # behind clock up one period at a time. The whole customer runs in one transaction, so
  # the consumer sees the customer's whole set or nothing (completeness), and the clock
  # never advances without a durable record (money-safety). The per-customer advisory
  # lock serialises concurrent runs; the unique (product item, period_from) index is the
  # idempotency backstop.
  #
  # A customer holds few items, so plain create!/update! is both readable and fast; the
  # scale lives in the fan-out (one job per customer), not in bulk-writing one customer.
  #
  # Pricing is NOT resolved here — the processor re-resolves the rate at period_from.
  class ScheduleService < BaseService
    Result = BaseResult[:billing_cycles]

    def initialize(customer:, up_to: Time.current)
      @customer = customer
      @up_to = up_to
      super
    end

    def call
      result.billing_cycles = []

      customer.with_advisory_lock("billing_cycle_schedule_customer_#{customer.id}") do
        ActiveRecord::Base.transaction do
          due_items.each { |subscription_rate_card| schedule(subscription_rate_card) }
        end
      end

      result
    end

    private

    attr_reader :customer, :up_to

    def due_items
      customer.subscription_rate_cards
        .where(ended_at: nil)
        .where("next_billing_at <= ?", up_to)
    end

    def schedule(subscription_rate_card)
      while subscription_rate_card.next_billing_at <= up_to
        rate = resolve_rate(subscription_rate_card)
        # Can't compute the next boundary without an interval; leave the clock for a
        # later retry once the catalog is fixed rather than skipping the period.
        break unless rate

        dates = BillingPeriods::DatesService.from_subscription_rate_card(
          subscription_rate_card, rate:, billing_at: subscription_rate_card.next_billing_at
        )

        result.billing_cycles << BillingCycle.create!(
          organization: subscription_rate_card.organization,
          subscription: subscription_rate_card.subscription,
          customer:,
          subscription_rate_card:,
          billing_at: subscription_rate_card.next_billing_at,
          # Clamp to the item start so a mid-cycle start bills only the remainder.
          period_from: [dates.period_from, started_at_floor(subscription_rate_card)].max,
          period_to: dates.period_to
        )
        subscription_rate_card.update!(next_billing_at: dates.next_billing_at)
      end
    end

    def started_at_floor(subscription_rate_card)
      subscription_rate_card.started_at
        .in_time_zone(customer.applicable_timezone)
        .beginning_of_day
        .utc
    end

    def resolve_rate(subscription_rate_card)
      SubscriptionRateCards::ResolveRateService
        .call(subscription_rate_card:, datetime: subscription_rate_card.next_billing_at)
        .rate
    end
  end
end
