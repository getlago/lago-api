# frozen_string_literal: true

module BillingPeriods
  # Selects the billing-period date service matching the rate card timing.
  class DatesService < BaseService
    Result = BaseResult[:next_billing_at, :periods]

    # Date generation knobs shared by advance and arrears services.
    # Defaults match the scheduler path: customer dates are evaluated in UTC,
    # only periods overlapping the requested range are returned, and interval
    # changes start a new billing calendar from the transition date.
    #
    # exclude_out_of_range:
    # - true: keep only periods overlapping `range`. Use for billing runs, so a
    #   schedule call for Sep 10 does not return historical or future periods.
    # - false: return every generated period up to the range end. Use for the
    #   v2 testing `cycles` endpoint, where callers want to inspect the full
    #   timeline from subscription start.
    #
    # realign_billing_anchor:
    # - false: keep using the original billing anchor when an interval changes.
    #   Example: monthly anchor Jan 1, then 2 weekly cycles ending Feb 15, then
    #   monthly again => the next monthly period ends Feb 28
    # - true: when the interval changes, use the transition date as the new
    #   anchor. Same example => the next monthly period runs Feb 15 to Mar 14
    #   and then continues on the 15th of each month
    #
    # termination:
    # - false: select the date service from the rate card billing timing
    # - true: generate every period overlapping `range`, regardless of billing timing.
    #   Use for termination, where a future cancellation may need several unbilled
    #   cycles up to the termination instant.
    Options = Data.define(:timezone, :exclude_out_of_range, :realign_billing_anchor, :termination) do
      def self.default
        new(timezone: "UTC", exclude_out_of_range: true, realign_billing_anchor: true, termination: false)
      end
    end

    # One logical billing cycle for a subscription rate card. It owns the
    # cycle index and phase resolution; rate effective dates may split it into
    # several Periods without advancing this index.
    Cycle = Data.define(
      :index,
      :period_from,
      :period_to,
      :next_billing_at,
      :rate_phase
    ) do
      def rate_override
        rate_phase&.rate_override
      end
    end

    # A concrete date slice priced with one catalog rate. Several periods can
    # belong to the same Cycle when a rate effective date cuts the logical
    # billing cycle.
    Period = Data.define(
      :period_from,
      :period_to,
      :next_billing_at,
      :rate,
      :cycle,
      :proration_ratio,
      :consumed_ratio
    ) do
      def billing_at
        billing_boundary = if rate.rate_card.advance?
          period_from
        else
          period_to
        end

        [billing_boundary, Time.current].max
      end

      delegate :index, to: :cycle, prefix: true

      delegate :rate_phase, to: :cycle

      delegate :rate_override, to: :cycle

      def rate_properties
        (rate_override || rate).properties
      end
    end

    def self.from_subscription_rate_card(
      subscription_rate_card,
      rates:,
      range:, rate_phases: SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases: []),
      options: Options.default
    )
      call(
        options:,
        subscription_rate_card:,
        rates:,
        rate_phases:,
        range:
      )
    end

    def initialize(
      subscription_rate_card:,
      rates:,
      range:,
      options: Options.default,
      rate_phases: SubscriptionRateCards::ResolveRatePhasesService::RatePhases.new(phases: [])
    )
      @subscription_rate_card = subscription_rate_card
      @options = options
      @billing_anchor_date = subscription_rate_card.billing_anchor_date
      @billing_timing = subscription_rate_card.rate_card.billing_timing.to_sym
      # Anchored on the card, not on the current version: a units change opens a new row, and
      # using that row's own start would clip every period to the moment the quantity last
      # changed.
      @started_at = subscription_rate_card.card_started_at.in_time_zone(options.timezone).beginning_of_day.utc
      @rates = rates
      @rate_phases = rate_phases
      @range = range
      super
    end

    def call
      dates = dates_service.call(
        billing_anchor_date:,
        options:,
        started_at:,
        subscription_rate_card:,
        rates:,
        rate_phases:,
        range:
      )

      result.periods = dates.periods
      result.next_billing_at = dates.next_billing_at
      result
    end

    private

    attr_reader :billing_anchor_date, :billing_timing, :options, :started_at, :subscription_rate_card, :rates, :rate_phases, :range

    def arrears?
      billing_timing == :arrears
    end

    def dates_service
      return Dates::TerminationService if options.termination

      case billing_timing
      when :arrears
        Dates::ArrearsService
      when :advance
        Dates::AdvanceService
      else
        raise ArgumentError, "Invalid billing timing: #{billing_timing}"
      end
    end
  end
end
