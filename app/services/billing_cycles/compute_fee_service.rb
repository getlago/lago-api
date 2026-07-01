# frozen_string_literal: true

module BillingCycles
  # Builds the (unsaved) fee for one billing cycle: resolves the rate at the period
  # start, then prices it. For now it handles fixed (subscription) items priced with
  # the standard model; usage aggregation is a later slice.
  #
  # Proration: with rate_card.proration == "full", a partial period (a clamped first
  # period or a mid-period termination) is charged pro-rata by day count
  # (cycle_days / full_period_days). With "none" the full period amount is charged.
  #
  #   $20/month, period [Jun 1, Jun 30] (30/30 days) => $20.00
  #   $20/month, period [Jun 1, Jun 23] (23/30 days) => $15.33
  class ComputeFeeService < BaseService
    Result = BaseResult[:fee]

    def initialize(billing_cycle:)
      @billing_cycle = billing_cycle
      super
    end

    def call
      return result.not_found_failure!(resource: "rate") unless rate

      result.fee = Fee.new(
        organization: billing_cycle.organization,
        subscription:,
        invoiceable: product_item,
        fee_type: :product_item,
        rate_card_rate: rate,
        amount_cents:,
        amount_currency: currency,
        unit_amount_cents:,
        units:,
        taxes_amount_cents: 0,
        precise_amount_cents: BigDecimal(amount_cents),
        # The actual service window, shown as the billing period on the invoice
        # (same keys the legacy engine stores).
        properties: {
          "from_datetime" => billing_cycle.period_from.iso8601(3),
          "to_datetime" => billing_cycle.period_to.iso8601(3)
        }
      )
      result
    end

    private

    attr_reader :billing_cycle

    delegate :subscription_product_item, to: :billing_cycle
    delegate :subscription, :product_item, to: :subscription_product_item

    def rate
      @rate ||= SubscriptionProductItems::ResolveRateService
        .call(subscription_product_item:, datetime: billing_cycle.period_from)
        .rate
    end

    def currency
      rate.rate_card.currency
    end

    def amount_cents
      (full_amount_cents * proration_ratio).round
    end

    def full_amount_cents
      unit_amount_cents * units
    end

    def unit_amount_cents
      (BigDecimal(rate.rate_properties.fetch("amount", "0")) * subunit).round
    end

    def units
      subscription_product_item.units || plan_product_item&.units || 0
    end

    # 1 for a full period; the prorated fraction for a partial period. The day math
    # lives on Boundaries (the billing calendar), matching the legacy engine.
    def proration_ratio
      return 1 unless rate.rate_card.proration_full?

      boundaries.proration_ratio(billing_cycle.period_from, billing_cycle.period_to)
    end

    def boundaries
      @boundaries ||= BillingPeriods::Boundaries.new(
        billing_anchor_date: subscription_product_item.billing_anchor_date,
        interval_count: rate.billing_interval_count,
        interval_unit: rate.billing_interval_unit,
        timezone: subscription.customer.applicable_timezone
      )
    end

    def subunit
      Money::Currency.new(currency).subunit_to_unit
    end

    def plan_product_item
      subscription.plan&.plan_product_items&.find_by(product_item_id: product_item.id)
    end
  end
end
