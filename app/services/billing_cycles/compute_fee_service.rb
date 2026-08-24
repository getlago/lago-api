# frozen_string_literal: true

module BillingCycles
  # Builds the (unsaved) fee for one billing cycle. The scheduler stores the exact
  # pricing records on the cycle, so processing retries price the same slice without
  # resolving the catalog timeline again.
  #
  # Proration: when rate_card.proration is true, a partial period (a clamped first
  # period or a mid-period termination) is charged pro-rata by day count
  # (cycle_days / full_period_days). When false the full period amount is charged.
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
        invoiceable: product,
        fee_type: :product,
        rate_card_rate:,
        rate_override:,
        amount_cents:,
        amount_currency: currency,
        unit_amount_cents: fee_unit_amount_cents,
        precise_unit_amount:,
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

    delegate :currency, :rate, :rate_card_rate, :rate_override, :subscription_rate_card, to: :billing_cycle
    delegate :subscription, :product, to: :subscription_rate_card

    def amount_cents
      (full_amount_cents * proration_ratio).round
    end

    def full_amount_cents
      rate_amount_cents * units
    end

    # The catalog per-unit rate in cents (before proration).
    def rate_amount_cents
      (BigDecimal(billing_cycle.rate_properties.fetch("amount", "0")) * subunit).round
    end

    # Effective per-unit amount shown on the invoice — proration baked in so that
    # unit price × units == amount (matches the legacy engine). Full period => rate.
    def fee_unit_amount_cents
      return 0 if units.zero?

      (amount_cents / units).round
    end

    def precise_unit_amount
      return BigDecimal(0) if units.zero?

      BigDecimal(amount_cents) / units / subunit
    end

    # Resolved over the cycle's own window rather than read off the card, because a units
    # change mid-period leaves several versions covering that window. Composes with
    # proration_ratio: this answers "which quantity", the ratio answers "how much of the
    # period the window covers".
    def units
      @units ||= SubscriptionRateCards::ResolveUnitsService.call!(
        subscription_rate_card:,
        from: billing_cycle.period_from,
        to: billing_cycle.period_to
      ).units
    end

    # 1 for a full period; the prorated fraction for a partial period. The day math
    # lives on Boundaries (the billing calendar), matching the legacy engine.
    def proration_ratio
      return 1 unless subscription_rate_card.proration?

      boundaries.proration_ratio(billing_cycle.period_from, billing_cycle.period_to)
    end

    def boundaries
      @boundaries ||= BillingPeriods::Boundaries.new(
        billing_anchor_date: subscription_rate_card.billing_anchor_date,
        interval_count: rate.billing_interval_count,
        interval_unit: rate.billing_interval_unit,
        timezone: subscription.customer.applicable_timezone
      )
    end

    def subunit
      Money::Currency.new(currency).subunit_to_unit
    end
  end
end
