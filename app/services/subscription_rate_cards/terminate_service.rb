# frozen_string_literal: true

module SubscriptionRateCards
  # Terminates a single product-catalog item.
  #
  # Arrears items create pending BillingCycles for periods overlapping the termination
  # window. The final period runs to the end of the termination DAY — a day entered is a
  # day paid for, see Billing::TerminationDay — and is left pending for the clock processor
  # to invoice. The item's next_billing_at is set to terminated_at so the due-items scope
  # will no longer treat it as an unbilled future cycle.
  #
  # Advance items do not create a BillingCycle: the current period was already billed
  # up front. This service only sets ended_at; the subscription-level termination flow
  # handles any unused-period credit note separately.
  class TerminateService < BaseService
    # One microsecond, the resolution of a timestamp column: the gap between a window's
    # exclusive end and the last instant it actually covers.
    PERIOD_END_PRECISION = Rational(1, 1_000_000)

    Result = BaseResult[:subscription_rate_card, :billing_cycles]

    def initialize(subscription_rate_card:, terminated_at: Time.current)
      @subscription_rate_card = subscription_rate_card
      @terminated_at = terminated_at
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_rate_card") unless subscription_rate_card

      result.billing_cycles = []
      return result if subscription_rate_card.ended_at.present?

      ActiveRecord::Base.transaction do
        result.billing_cycles = final_cycles
        subscription_rate_card.update!(termination_attributes)
      end

      result.subscription_rate_card = subscription_rate_card
      result
    end

    private

    attr_reader :subscription_rate_card, :terminated_at

    delegate :organization, :subscription, :customer, to: :subscription_rate_card

    def termination_attributes
      attributes = {ended_at: terminated_at}
      return attributes unless arrears?

      attributes.merge(next_billing_at: terminated_at)
    end

    def final_cycles
      return [] unless arrears?
      return [] unless schedule

      final_segments.map { |segment| billing_cycle_for(segment) }
    end

    # Every segment still unbilled when the termination window opened.
    #
    # Asked as of `billed_through`, not the termination instant: the final segment closes at
    # the end of the termination day, so for arrears that is also when it falls due, and
    # asking any earlier leaves it out of the due list entirely.
    #
    # The test is on the close — a segment that closed before the window opened was billed
    # by the regular clock, and everything from there on is termination's to emit. The window
    # opens at the termination for a past or immediate one and at `now` for a future one,
    # which is what keeps termination from reaching backwards for cycles the clock skipped.
    def final_segments
      schedule.segments_due_by(billed_through).select { it.ended_at >= window_opens_at }
    end

    def window_opens_at
      @window_opens_at ||= [Time.current, terminated_at].min
    end

    # Built with the end of the termination day as its end, so the last cycle is already
    # clipped to it and carries the prorated share of the days actually served.
    #
    # A card whose rate card holds no rate has no cycles to emit and is terminated all the
    # same, so a failed build is nil rather than an exception.
    def schedule
      return @schedule if defined?(@schedule)

      build = Billing::BuildScheduleService.call(subscription_rate_card:, ends_at: billed_through)
      @schedule = build.success? ? build.schedule : nil
    end

    # How far billing runs: the end of the day the termination falls in, in the customer's
    # timezone. `ended_at` on the card keeps the raw instant — when service stopped and how
    # far it is billed are different facts.
    def billed_through
      @billed_through ||= Billing::TerminationDay.billed_through(terminated_at, timezone: customer.applicable_timezone)
    end

    def billing_cycle_for(segment)
      BillingCycle.create!(
        organization:,
        subscription:,
        customer:,
        subscription_rate_card:,
        billing_at: terminated_at,
        period_from: segment.started_at,
        period_to: inclusive_end_of(segment.ended_at),
        rate_card_rate: segment.rate,
        rate_override: segment.rate_override,
        rate_properties: (segment.rate_override || segment.rate).properties,
        proration_ratio: segment.proration_ratio
      )
    end

    # The engine's windows are half-open; the column is not.
    #
    # The clipped final cycle is the exception, and deliberately so: the window is a fact
    # about SERVICE and the ratio is a decision about BILLING. Service stopped at the
    # termination instant, so that is what the columns record — usage metering reads these
    # boundaries to decide which events fall inside the period, and an end stretched to
    # midnight would sweep in events from after the subscription was gone.
    #
    # The termination day is still paid for in full: that lives in proration_ratio, which
    # the schedule computed over the window ending at `billed_through`. The two disagree by
    # design, which is why they are written from different values here.
    def inclusive_end_of(ended_at)
      return terminated_at if ended_at == billed_through

      ended_at - PERIOD_END_PRECISION
    end

    def arrears?
      subscription_rate_card.rate_card.arrears?
    end
  end
end
