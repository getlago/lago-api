# frozen_string_literal: true

module BillingPeriods
  # Computes the first billing period and the initial next_billing_at at subscription
  # creation (forward-looking), as opposed to DatesService which resolves the period
  # being billed at a given moment (backward-looking).
  #
  # The first period starts when the subscription starts. If the subscription starts
  # mid-cycle (started_at later than the anchor boundary), the first period is the
  # partial remainder [started_at, next boundary).
  #
  #   arrears -> first bill at the end of the first period (the next boundary)
  #   advance -> first bill immediately, at the start of the first period
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

    # The first period starts the day the subscription starts (partial when the
    # subscription starts mid-cycle).
    def period_from
      @period_from ||= started_at.in_time_zone(timezone).beginning_of_day.utc
    end

    # The first boundary strictly after the subscription start: the end of the first
    # period and, for arrears, the first billing instant.
    def next_boundary
      @next_boundary ||= boundaries.at(boundaries.index_on_or_before(started_at.in_time_zone(timezone)) + 1)
    end
  end
end
