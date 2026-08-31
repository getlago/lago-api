# frozen_string_literal: true

module BillingSegments
  # Producer lane, scoped to ONE customer. It selects subscription rate cards whose
  # next_billing_at is due within the scheduling range, loads the dependencies needed
  # to bill each period, writes pending BillingSegment rows, and advances each item's
  # clock. Termination final segments are not scheduled here; they are created by
  # SubscriptionRateCards::TerminateService.
  #
  # A BillingSegment is the durable processing contract: it carries the resolved rate,
  # optional override, pricing unit, rate properties snapshot, period boundaries, and
  # billing date. Downstream processing should use those segment dependencies instead of
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
  # computed later from the dependencies and snapshots stored on each billing segment.
  class ScheduleService < BaseService
    OVERLAP_CONSTRAINT = "billing_segments_no_overlapping_periods"
    UNIQUE_PERIOD_INDEX = "index_billing_segments_on_product_and_period"

    Result = BaseResult[:billing_segments]

    def initialize(customer:, range: nil)
      @customer = customer
      @requested_range = range
      super
    end

    def call
      result.billing_segments = []

      customer.with_advisory_lock("billing_segment_schedule_customer_#{customer.id}") do
        ActiveRecord::Base.transaction do
          due_items.each { |subscription_rate_card| schedule(subscription_rate_card) }
        end
      end

      result
    rescue ActiveRecord::StatementInvalid => e
      raise unless billing_segment_period_conflict?(e)

      result.billing_segments = []
      result.single_validation_failure!(field: :billing_segment, error_code: "overlapping_periods")
    end

    private

    attr_reader :customer, :requested_range

    # The clock runs without a window: everything matured by now is due. Billing a chosen
    # window passes one, and then the window decides — it may deliberately reach back past
    # what the card's own clock says.
    def billed_until
      @billed_until ||= requested_range ? window.end : Time.current
    end

    def window
      @window ||= requested_range.begin.to_date.beginning_of_day.utc...
        requested_range.end.to_date.end_of_day.utc
    end

    def due_items
      customer.subscription_rate_cards
        .due_for_range(billed_until..billed_until)
        .includes(:rate_phases, subscription: {plan: {applied_rate_cards: :rate_phases}})
    end

    def schedule(subscription_rate_card)
      rates = rates_for(subscription_rate_card)
      return if rates.empty?

      build = ::Billing::Schedules::BuildService.call(
        subscription_rate_card:,
        plan_rate_cards: plan_rate_cards_for(subscription_rate_card.subscription)
      )
      return if build.failure?

      cycles = due_cycles(build.schedule, subscription_rate_card)
      # Nothing due means nothing to move the clock past: leaving it where it is keeps the
      # card in the queue for the run that does find something.
      return if cycles.empty?

      cycles.each do |cycle|
        ::Billing::Segments.within(cycle.from...cycle.to, rates:).each do |segment|
          result.billing_segments << persist(subscription_rate_card, cycle, segment)
        end
      end

      advance_clock(subscription_rate_card, build.schedule.next_due_at(billed_until))
    end

    # Two questions, and only one of them looks at the card's clock. Without a window the
    # clock is the floor, so a run bills what has matured since the last one. With a window
    # the caller chose the period on purpose and the floor would silently narrow it.
    def due_cycles(schedule, subscription_rate_card)
      return schedule.cycles_overlapping(window) if requested_range

      schedule
        .cycles_due_by(billed_until)
        .select { |cycle| cycle.due_at >= subscription_rate_card.next_billing_at }
    end

    def persist(subscription_rate_card, cycle, segment)
      BillingSegment.create!(
        organization: subscription_rate_card.organization,
        subscription: subscription_rate_card.subscription,
        customer:,
        subscription_rate_card:,
        billing_at: [cycle.due_at, Time.current].max,
        period_from: segment.from,
        period_to: inclusive_end(segment.to),
        rate_card_rate: segment.rate,
        rate_override: cycle.phase.override,
        pricing_unit: pricing_unit_for(subscription_rate_card),
        rate_properties: (cycle.phase.override || segment.rate).properties,
        proration_ratio: proration_ratio(subscription_rate_card, cycle, segment)
      )
    end

    # Windows are half-open in the engine and stored inclusive, so the stored end is the
    # last instant the segment actually covers — a microsecond before it closes.
    def inclusive_end(instant)
      instant - Rational(1, 1_000_000)
    end

    # 1 for a card that does not prorate: a partial window still owes the whole fee.
    def proration_ratio(subscription_rate_card, cycle, segment)
      return 1 unless subscription_rate_card.proration?

      cycle.calendar.elapsed_ratio(segment.from, segment.to)
    end

    # Every rate the card has ever carried: which one prices a segment is decided by its
    # effective date, so narrowing the set here would hide the one in force.
    def rates_for(subscription_rate_card)
      subscription_rate_card.rate_card.rates.order(:effective_from)
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
      return if subscription_rate_card.next_billing_at > billed_until
      return if next_billing_at <= subscription_rate_card.next_billing_at

      subscription_rate_card.update!(next_billing_at: next_billing_at)
    end

    def billing_segment_period_conflict?(error)
      error_message = error.cause&.message || error.message

      error_message.include?(OVERLAP_CONSTRAINT) || error_message.include?(UNIQUE_PERIOD_INDEX)
    end
  end
end
