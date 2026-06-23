# frozen_string_literal: true

module BillingPeriods
  # Resolves the billing period for a reference moment (`billing_at`) and the next
  # billing instant.
  #
  # With B = the boundary on or before billing_at (in the customer timezone):
  #   arrears -> [B - interval, B)   (bill the period that just closed)
  #   advance -> [B, B + interval)   (bill the period that just started)
  #   next_billing_at = B + interval
  #
  # period_from is the start of the period (beginning of day); period_to is the
  # INCLUSIVE end (end_of_day of the final day), matching the legacy engine.
  # Boundary math lives in BillingPeriods::Boundaries.
  class DatesService < BaseService
    Result = BaseResult[:period_from, :period_to, :next_billing_at]

    # Convenience entry point for callers that hold the domain objects.
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

    # Which period billing_at falls in.
    def current_index
      @current_index ||= boundaries.index_on_or_before(billing_at.in_time_zone(timezone))
    end

    # Start of the billed period (beginning of day).
    def period_start
      (arrears? ? boundaries.at(current_index - 1) : boundaries.at(current_index)).utc
    end

    # Inclusive end of the billed period (end_of_day of its final day).
    def period_end
      exclusive_end = arrears? ? boundaries.at(current_index) : boundaries.at(current_index + 1)
      (exclusive_end - 1.second).end_of_day.utc
    end
  end
end
