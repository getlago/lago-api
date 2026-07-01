# frozen_string_literal: true

module BillingPeriods
  # Resolves the billing period being billed at a reference moment (`billing_at`) and
  # the next billing instant. Backward-looking: it answers "given this moment, which
  # period do we bill?"
  #
  # With B = the boundary on or before billing_at (in the customer timezone):
  #   arrears -> [B - interval, B)   (bill the period that just closed)
  #   advance -> [B, B + interval)   (bill the period that just started)
  #   next_billing_at = the next boundary
  #
  # period_from is the start of the period; period_to is the INCLUSIVE end
  # (end_of_day of the final day), matching the legacy engine. Boundary math lives in
  # BillingPeriods::Boundaries.
  #
  # Running example below: anchor 2022-02-01, monthly, billing_at 2022-03-01.
  #   arrears => [2022-02-01, 2022-02-28 23:59:59], next 2022-04-01
  #   advance => [2022-03-01, 2022-03-31 23:59:59], next 2022-04-01
  class DatesService < BaseService
    Result = BaseResult[:period_from, :period_to, :next_billing_at]

    def self.from_subscription_product_item(subscription_product_item, rate:, billing_at:)
      call(
        billing_anchor_date: subscription_product_item.billing_anchor_date,
        interval_count: rate.billing_interval_count,
        interval_unit: rate.billing_interval_unit,
        billing_timing: rate.rate_card.billing_timing,
        timezone: subscription_product_item.subscription.customer.applicable_timezone,
        billing_at:
      )
    end

    def initialize(billing_anchor_date:, interval_count:, interval_unit:, billing_timing:, timezone:, billing_at:)
      @boundaries = Boundaries.new(billing_anchor_date:, interval_count:, interval_unit:, timezone:)
      @billing_timing = billing_timing.to_sym
      @timezone = timezone
      @billing_at = billing_at
      super
    end

    def call
      result.period_from = period_start
      result.period_to = period_end
      result.next_billing_at = boundaries.at(current_index + 1).utc
      result
    end

    private

    attr_reader :boundaries, :billing_timing, :timezone, :billing_at

    def arrears?
      billing_timing == :arrears
    end

    # Index of the period billing_at falls in (B). Converts billing_at to the customer
    # timezone first, so the period is resolved in local time.
    #   billing_at 2022-03-01 => current_index 1 (boundary 2022-03-01)
    def current_index
      @current_index ||= boundaries.index_on_or_before(billing_at.in_time_zone(timezone))
    end

    # Start of the billed period. arrears bills the period that just closed, so it
    # starts one boundary before B; advance bills the period starting at B.
    #   arrears => boundary 0 = 2022-02-01    advance => boundary 1 = 2022-03-01
    def period_start
      (arrears? ? boundaries.at(current_index - 1) : boundaries.at(current_index)).utc
    end

    # Inclusive end of the billed period: the last instant of its final day. The
    # exclusive boundary (B for arrears, B+interval for advance) minus one second, rounded to end_of_day
    #   arrears => 2022-02-28 23:59:59    advance => 2022-03-31 23:59:59
    def period_end
      exclusive_end = arrears? ? boundaries.at(current_index) : boundaries.at(current_index + 1)
      (exclusive_end - 1.second).end_of_day.utc
    end
  end
end
