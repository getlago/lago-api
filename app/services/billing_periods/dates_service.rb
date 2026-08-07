# frozen_string_literal: true

module BillingPeriods
  # Selects the billing-period date service matching the rate card timing.
  class DatesService < BaseService
    Result = BaseResult[:next_billing_at, :periods]
    Period = Data.define(:period_from, :period_to, :next_billing_at, :rate)

    def self.from_subscription_rate_card(subscription_rate_card, rates:, range: nil, exclude_out_of_range: false)
      timezone = subscription_rate_card.subscription.customer.applicable_timezone

      call(
        billing_anchor_date: subscription_rate_card.billing_anchor_date,
        billing_timing: rates.first.rate_card.billing_timing,
        timezone:,
        billing_at: subscription_rate_card.next_billing_at,
        started_at: subscription_rate_card.started_at.in_time_zone(timezone).beginning_of_day.utc,
        rates:,
        range:,
        exclude_out_of_range:
      )
    end

    def initialize(
      billing_anchor_date:,
      billing_timing:,
      timezone:,
      billing_at:,
      started_at:,
      rates:,
      range:,
      exclude_out_of_range: false
    )
      @billing_anchor_date = billing_anchor_date
      @billing_timing = billing_timing.to_sym
      @timezone = timezone
      @billing_at = billing_at
      @started_at = started_at
      @rates = rates
      @range = range
      @exclude_out_of_range = exclude_out_of_range
      super
    end

    def call
      dates = dates_service.call(
        billing_anchor_date:,
        timezone:,
        started_at:,
        rates:,
        range:,
        exclude_out_of_range:
      )

      result.periods = dates.periods
      result.next_billing_at = dates.next_billing_at
      result
    end

    private

    attr_reader :billing_anchor_date, :billing_timing, :timezone, :billing_at, :started_at, :rates, :range, :exclude_out_of_range

    def arrears?
      billing_timing == :arrears
    end

    def dates_service
      arrears? ? Dates::ArrearsService : Dates::AdvanceService
    end
  end
end
