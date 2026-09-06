# frozen_string_literal: true

module BillingCycles
  # Producer lane, scoped to ONE customer. It selects subscription rate cards whose
  # next_billing_at is due within the scheduling range, loads the dependencies needed
  # to bill each period, writes pending BillingCycle rows, and advances each item's
  # clock. Termination final cycles are not scheduled here; they are created by
  # SubscriptionRateCards::TerminateService.
  #
  # A BillingCycle is the durable processing contract: it carries the resolved rate,
  # optional override, pricing unit, rate properties snapshot, period boundaries, and
  # billing date. Downstream processing should use those cycle dependencies instead of
  # resolving product-catalog pricing again.
  #
  # The whole customer runs in one transaction, so the consumer sees the customer's
  # whole set or nothing (completeness), and the clock never advances without a
  # durable record (money-safety). The per-customer advisory lock serialises
  # concurrent runs; the unique (product, period_from) index is the idempotency
  # backstop.
  #
  # A customer holds few items, so plain create!/update! is both readable and fast; the
  # scale lives in the fan-out (one job per customer), not in bulk-writing one customer.
  #
  # Rate effective dates are used only to split service periods. Pricing is still
  # computed later from the dependencies and snapshots stored on each billing cycle.
  class ScheduleService < BaseService
    OVERLAP_CONSTRAINT = "billing_cycles_no_overlapping_periods"
    UNIQUE_PERIOD_INDEX = "index_billing_cycles_on_product_and_period"
    # One microsecond, the resolution of a timestamp column: the gap between a window's
    # exclusive end and the last instant it actually covers.
    PERIOD_END_PRECISION = Rational(1, 1_000_000)

    Result = BaseResult[:billing_cycles]

    def initialize(customer:, range: nil)
      @customer = customer
      @requested_range = range
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
    rescue ActiveRecord::StatementInvalid => e
      raise unless billing_cycle_period_conflict?(e)

      result.billing_cycles = []
      result.single_validation_failure!(field: :billing_cycle, error_code: "overlapping_periods")
    end

    private

    attr_reader :customer, :requested_range

    def range
      @range ||= requested_range || default_range
    end

    # Clock and activation jobs schedule without an explicit window. Start from the
    # customer's earliest seeded item clock so backdated advance subscriptions bill the
    # cycle due at subscription start, not a one-day "today" window.
    def default_range
      billing_at = customer.subscription_rate_cards.minimum(:next_billing_at)
      range_begin = [billing_at, Time.current].compact.min

      range_begin..Time.current
    end

    def due_items
      customer.subscription_rate_cards
        .due_for_range(range)
        .includes(:rate_phases, subscription: {plan: {applied_rate_cards: :rate_phases}})
    end

    def schedule(subscription_rate_card)
      build = Billing::BuildScheduleService.call(
        subscription_rate_card:,
        plan_rate_card: plan_rate_card_for(subscription_rate_card)
      )
      return unless build.success?

      segments = due_segments(build.schedule, subscription_rate_card)
      return if segments.empty?

      # TODO: Consider moving this loop to import! or batch inserting BillingCycle rows.
      segments.each do |segment|
        result.billing_cycles << billing_cycle_for(subscription_rate_card, segment)
      end

      advance_clock(subscription_rate_card, build.schedule.next_billing_at(after: range_end))
    end

    # Everything the schedule owes by the end of the range that the caller's window asks
    # for and the item's clock has not already paid for.
    #
    # Two bounds, because they answer different questions. The clock is the durable record
    # of what has been billed, and it is what keeps a re-run over a wide range from
    # re-emitting history. The range is the caller's window, and it is what keeps a narrow
    # scheduling pass from reaching back over cycles it was not asked about.
    def due_segments(schedule, subscription_rate_card)
      schedule.segments_due_by(range_end)
        .select { it.billing_at >= subscription_rate_card.next_billing_at }
        .select { in_range?(it) }
    end

    # In the window when the segment still has service left in it, or when it falls due at
    # or after the window opens. That second half is the one deliberate change: the old
    # engine tested only the first, against an inclusive end, so an arrears cycle closing
    # exactly on the scheduling boundary read as "already past" and was dropped. That
    # boundary is normally the item's own clock, so the cycle was never billed, the clock
    # never moved, and the item stalled there permanently.
    def in_range?(segment)
      segment.ended_at > range_begin || segment.billing_at >= range_begin
    end

    def billing_cycle_for(subscription_rate_card, segment)
      BillingCycle.create!(
        organization: subscription_rate_card.organization,
        subscription: subscription_rate_card.subscription,
        customer:,
        subscription_rate_card:,
        billing_at: segment.billing_at,
        period_from: segment.started_at,
        period_to: inclusive_end_of(segment.ended_at),
        rate_card_rate: segment.rate,
        rate_override: segment.rate_override,
        pricing_unit: pricing_unit_for(subscription_rate_card),
        rate_properties: (segment.rate_override || segment.rate).properties,
        proration_ratio: segment.proration_ratio
      )
    end

    # The engine's windows are half-open; the column is not. `period_to` is stored as the
    # last instant covered because the overlap constraint reads it as inclusive, so writing
    # the exclusive end would make every pair of consecutive cycles collide.
    def inclusive_end_of(ended_at)
      ended_at - PERIOD_END_PRECISION
    end

    def range_begin
      @range_begin ||= range.begin.to_date.beginning_of_day.utc
    end

    def range_end
      @range_end ||= range.end.to_date.end_of_day.utc
    end

    # The plan entry that holds this card's phases, handed to the engine as a hint so it
    # does not look up once per item what one preloaded query already answered for the
    # whole subscription.
    def plan_rate_card_for(subscription_rate_card)
      plan_rate_cards_for(subscription_rate_card.subscription)
        .find { it.rate_card_id == subscription_rate_card.rate_card_id }
    end

    def plan_rate_cards_for(subscription)
      @plan_rate_cards_by_subscription_id ||= {}
      @plan_rate_cards_by_subscription_id[subscription.id] ||= subscription.plan.applied_rate_cards.to_a
    end

    def pricing_unit_for(subscription_rate_card)
      code = subscription_rate_card.rate_card.applied_pricing_unit_code
      return if code.blank?

      pricing_units_by_code[code]
    end

    def pricing_units_by_code
      @pricing_units_by_code ||= customer.organization.pricing_units.index_by(&:code)
    end

    def advance_clock(subscription_rate_card, next_billing_at)
      return unless next_billing_at
      return if subscription_rate_card.next_billing_at > range_end
      return if next_billing_at <= subscription_rate_card.next_billing_at

      subscription_rate_card.update!(next_billing_at: next_billing_at)
    end

    def billing_cycle_period_conflict?(error)
      error_message = error.cause&.message || error.message

      error_message.include?(OVERLAP_CONSTRAINT) || error_message.include?(UNIQUE_PERIOD_INDEX)
    end
  end
end
