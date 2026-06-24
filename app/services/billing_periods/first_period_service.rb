# frozen_string_literal: true

module BillingPeriods
  # Computes the first billing period and the initial next_billing_at at subscription
  # creation (forward-looking), as opposed to DatesService which resolves the period
  # being billed at a given moment (backward-looking).
  #
  # The first period is anchored to whichever is later — the subscription start or
  # `now`. Clamping to `now` is what stops a backdated start (started_at far in the
  # past) from back-billing the missed periods: it bills the *current* period forward,
  # matching the legacy engine. A subscription that genuinely starts mid-cycle still
  # gets a partial first period [started_at, next boundary).
  #
  #   arrears -> first bill at the end of the first period (the next boundary)
  #   advance -> first bill at the start of the first period
  class FirstPeriodService < BaseService
    Result = BaseResult[:period_from, :period_to, :next_billing_at]

    def self.from_subscription_product_item(subscription_product_item, rate:)
      call(
        billing_anchor_date: subscription_product_item.billing_anchor_date,
        interval_count: rate.billing_interval_count,
        interval_unit: rate.billing_interval_unit,
        billing_timing: rate.rate_card.billing_timing,
        timezone: subscription_product_item.subscription.customer.applicable_timezone,
        started_at: subscription_product_item.started_at
      )
    end

    def initialize(billing_anchor_date:, interval_count:, interval_unit:, billing_timing:, timezone:, started_at:)
      @boundaries = Boundaries.new(billing_anchor_date:, interval_count:, interval_unit:, timezone:)
      @billing_timing = billing_timing.to_sym
      @timezone = timezone
      @started_at = started_at
      super
    end

    def call
      result.period_from = period_from
      result.period_to = (next_boundary - 1.second).end_of_day.utc
      result.next_billing_at = arrears? ? next_boundary.utc : period_from
      result
    end

    private

    attr_reader :boundaries, :billing_timing, :timezone, :started_at

    def arrears?
      billing_timing == :arrears
    end

    # The first period starts at the subscription start, but never before the start of
    # the current period — so a backdated start bills the current period, not the gap.
    def period_from
      @period_from ||= [boundaries.at(current_index), started_at.in_time_zone(timezone).beginning_of_day].max.utc
    end

    def next_boundary
      @next_boundary ||= boundaries.at(current_index + 1)
    end

    # Anchor the first period to whichever is later, the subscription start or now.
    # Clamping to now is what prevents a backdated start from back-billing past periods.
    # TODO Time.current needs to be an argyment to be ease to manipulate if we need to run somehing in the past
    def current_index
      @current_index ||= boundaries.index_on_or_before([started_at, Time.current].max.in_time_zone(timezone))
    end
  end
end
