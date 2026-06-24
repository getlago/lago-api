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
        precise_amount_cents: BigDecimal(amount_cents)
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

    # 1 for a full period; cycle_days / full_period_days for a partial period when
    # the rate prorates.
    def proration_ratio
      return 1 unless rate.rate_card.proration_full?
      return 1 if cycle_days >= full_period_days

      cycle_days.fdiv(full_period_days)
    end

    def cycle_days
      (billing_cycle.period_to.to_date - billing_cycle.period_from.to_date).to_i + 1
    end

    # Length of the full boundary-to-boundary period this cycle belongs to.
    def full_period_days
      exclusive_end = billing_cycle.period_to.to_date + 1.day
      (exclusive_end - (exclusive_end - interval)).to_i
    end

    def interval
      rate.billing_interval_count.public_send(rate.billing_interval_unit)
    end

    def subunit
      Money::Currency.new(currency).subunit_to_unit
    end

    def plan_product_item
      subscription.plan&.plan_product_items&.find_by(product_item_id: product_item.id)
    end
  end
end
