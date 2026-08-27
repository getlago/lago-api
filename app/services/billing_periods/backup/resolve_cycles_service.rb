# frozen_string_literal: true

module BillingPeriods
  # The cycles a billing run should bill for one subscription rate card.
  #
  #   which periods does this run touch?   -> Calendar
  #   how is each one sliced by price?     -> #slice, below
  #
  # A period is May 1 to May 31. It normally yields one cycle. A rate whose effective_from
  # lands inside it yields two, each priced with its own rate and carrying its own share of
  # the period. Each cycle becomes one billing_cycles row and one fee.
  #
  # `claim_by` decides which periods the range takes and is the one argument worth stopping
  # on — see Timing::CLAIM_RULES. A billing run wants the default.
  class ResolveCyclesService < BaseService
    Result = BaseResult[:cycles, :next_billing_at]

    def initialize(
      subscription_rate_card:,
      rates:,
      range:,
      timezone:,
      claim_by: :billing_date,
      reanchor_on_interval_change: true,
      terminated_at: nil,
      rate_phases: SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases: [])
    )
      @subscription_rate_card = subscription_rate_card
      @rates = RateTimeline.new(rates)
      # Widened to whole days once, here. Everything downstream measures against instants and
      # takes this as given, so a caller passing dates and one passing times agree.
      @range = range.begin.to_date.beginning_of_day.utc..range.end.to_date.end_of_day.utc
      @timezone = timezone
      @claim_by = claim_by
      @reanchor_on_interval_change = reanchor_on_interval_change
      @terminated_at = terminated_at
      @timing = Timing.for(
        rate_card: subscription_rate_card.rate_card, range: @range, timezone:, terminated_at:, claim_by:
      )
      @rate_phases = rate_phases
      super
    end

    def call
      result.cycles = periods.flat_map { |period| slice(period) }
      result.next_billing_at = periods.map(&:next_billing_at).max
      result
    end

    private

    attr_reader :subscription_rate_card, :rates, :range, :timezone, :claim_by,
      :reanchor_on_interval_change, :terminated_at, :timing, :rate_phases

    def periods
      @periods ||= Calendar.new(
        anchor: subscription_rate_card.billing_anchor_date,
        started_at: calendar_starts_at,
        range:,
        timezone:,
        timing:,
        rates:,
        rate_phases:,
        reanchor_on_interval_change:
      ).periods
    end

    # When this card's billing CALENDAR began, which is not the same as when this row began.
    #
    # A subscription rate card is versioned: changing the units closes the current row and
    # opens a successor, so one card is several rows over time, each holding the quantity in
    # force across its own [started_at, ended_at). The calendar runs straight through those
    # boundaries — a units change on Mar 10 does not start a new March, it changes what March
    # costs — so it has to be anchored on the FIRST version's start.
    #
    # Today a card is one row and the two coincide. When versioning lands this must become the
    # earliest version's start, or every units change reanchors the calendar and restarts the
    # cycle index, which is what picks the rate phase. v2 had this as
    # SubscriptionRateCard#card_started_at (`card_versions.minimum(:started_at) || started_at`).
    def calendar_starts_at
      subscription_rate_card.started_at
    end

    # Cuts a period wherever the price changes hands inside it. One rate, one cycle.
    def slice(period)
      window_start, window_end = timing.window_for(period)
      return [] if window_start > window_end

      # Each cut opens a slice that runs to the next one; the nil closes the last against the
      # window's own end.
      cuts = [window_start, *rates.changes_within(window_start, window_end), nil]

      cuts.each_cons(2).filter_map do |starts_at, next_cut|
        rate = rates.at(starts_at)
        next unless rate

        ends_at = next_cut ? [moment_before(next_cut), window_end].min : window_end
        next if starts_at > ends_at

        cycle_for(period, rate, starts_at, ends_at)
      end
    end

    def cycle_for(period, rate, starts_at, ends_at)
      Cycle.new(
        starts_at:,
        ends_at:,
        billing_at: timing.billed_at(period),
        rate:,
        period:,
        proration_ratio: prorates? ? period.share_of(starts_at, ends_at) : 1,
        # How much of this slice the customer had used when service stopped, which is what
        # the credit for the unused remainder is taken against. Only a cancellation asks it —
        # a billing run has no unused remainder, so it gets no answer rather than a fraction
        # that looks like one.
        consumed_ratio: terminated_at && period.share_of(starts_at, terminated_at)
      )
    end

    def prorates?
      subscription_rate_card.rate_card.proration?
    end

    # The last instant before a rate takes effect at midnight.
    def moment_before(datetime)
      Time.zone.at(datetime.utc.to_r - Rational(1, 1_000_000)).utc
    end
  end
end
