# frozen_string_literal: true

module BillingCycles
  module Fees
    # Orchestrates billing-cycle fee creation. It calls the pricing and amount services,
    # then decorates the unsaved product fee and optional linked true-up fee. The
    # scheduler stores the exact pricing records on the cycle, so processing retries
    # price the same slice without resolving the catalog timeline again.
    #
    # Keep pricing and amount calculations out of this service; it should only coordinate
    # the services that compute them and map their results onto Fee records.
    #
    # Proration: the scheduler stores the fee ratio on the billing cycle. It is 1 for
    # a full period, or the prorated fraction for a partial period when the rate card
    # allows proration. When proration is disabled, the stored value is always 1.
    #
    #   $20/month, period [Jun 1, Jun 30] (30/30 days) => $20.00
    #   $20/month, period [Jun 1, Jun 23] (23/30 days) => $15.33
    class ComputeService < BaseService
      Result = BaseResult[:fee, :true_up_fee]

      def initialize(billing_cycle:)
        @billing_cycle = billing_cycle
        super
      end

      def call
        return result.not_found_failure!(resource: "rate") unless rate

        result.fee = fee
        result.true_up_fee = true_up_fee
        result
      end

      private

      attr_reader :billing_cycle

      delegate :currency, :rate, :rate_card_rate, :rate_override, :subscription_rate_card, to: :billing_cycle
      delegate :subscription, :product, to: :subscription_rate_card

      def fee
        @fee ||= Fee.new(
          organization: billing_cycle.organization,
          subscription:,
          invoiceable: product,
          fee_type: :product,
          rate_card_rate:,
          rate_override:,
          amount_cents: amount.amount_cents,
          amount_currency: currency,
          unit_amount_cents: amount.unit_amount_cents,
          precise_unit_amount: amount.precise_unit_amount,
          units: fee_units,
          taxes_amount_cents: 0,
          precise_amount_cents: amount.precise_amount_cents,
          amount_details: charge_model_result.amount_details,
          pricing_unit_usage: amount.pricing_unit_usage,
          properties: {
            "from_datetime" => billing_cycle.period_from.iso8601(3),
            "to_datetime" => billing_cycle.period_to.iso8601(3)
          }
        )
      end

      def true_up_fee
        return unless true_up_amount

        fee.dup.tap do |true_up_fee|
          true_up_fee.assign_attributes(
            amount_cents: true_up_amount.amount_cents,
            precise_amount_cents: true_up_amount.precise_amount_cents,
            units: 1,
            true_up_parent_fee: fee,
            unit_amount_cents: true_up_amount.unit_amount_cents,
            precise_unit_amount: true_up_amount.precise_unit_amount,
            pricing_unit_usage: true_up_amount.pricing_unit_usage
          )
        end
      end

      def amount
        return incremental_amount if incremental?

        fee_amounts.amount
      end

      # A pay-in-advance increase: the period was already invoiced, so this cycle owes only
      # the difference between the new position and what the watermark already covers.
      # Arrears never reaches this — its whole period is billed once, at the end.
      def incremental?
        return false unless subscription_rate_card.rate_card.advance?

        watermark.positive?
      end

      def watermark
        @watermark ||= BillingCycles::ResolveWatermarkService.call!(billing_cycle:).units
      end

      def incremental_amount
        @incremental_amount ||= begin
          delta = BillingCycles::Fees::AdvanceDeltaService.call!(
            billing_cycle:,
            units:,
            already_billed_units: watermark
          )

          amount_cents = (delta.amount * Money::Currency.new(currency).subunit_to_unit).round

          BillingCycles::Fees::AmountsService::Amount.new(
            amount_cents:,
            precise_amount_cents: BigDecimal(amount_cents),
            unit_amount_cents: delta.billable_units.zero? ? 0 : (amount_cents / delta.billable_units).round,
            precise_unit_amount: delta.billable_units.zero? ? BigDecimal(0) : BigDecimal(amount_cents) / delta.billable_units / Money::Currency.new(currency).subunit_to_unit,
            pricing_unit_usage: nil
          )
        end
      end

      def true_up_amount
        fee_amounts.true_up_amount
      end

      def fee_amounts
        @fee_amounts ||= BillingCycles::Fees::AmountsService.call!(
          billing_cycle:,
          charge_model_result:,
          currency: Money::Currency.new(currency),
          units:
        )
      end

      # Resolved over the cycle's own window rather than read off the card, because a units
      # change mid-period leaves several versions covering that window.
      def resolved_units
        @resolved_units ||= SubscriptionRateCards::ResolveUnitsService.call!(
          subscription_rate_card:,
          from: billing_cycle.period_from,
          to: billing_cycle.period_to
        )
      end

      # What the amount is computed from: the day-weighted quantity. Composes with
      # proration_ratio — this answers "which quantity", the ratio answers "how much of the
      # period the window covers".
      def billable_units
        resolved_units.units
      end

      # What the invoice line reports, and what selects the tier. A quantity is fractional in
      # time but a seat is not, so the line shows whole seats and the time-weighting is
      # absorbed into the unit price, which is derived as amount / units. Without proration
      # the two are the same number.
      #
      # An incremental charge reads the quantity off its OWN version instead. Resolving over
      # the window would pick up changes made after it — the window runs to the period end,
      # so a later increase sits inside it — and bill this charge for a quantity that was not
      # yet in force when it was raised.
      def units
        return BigDecimal((subscription_rate_card.units || 0).to_s) if incremental?

        resolved_units.closing_units
      end

      # An incremental charge bills only what sits above the watermark, so that is what the
      # line reports too.
      def fee_units
        return units unless incremental?

        [units - watermark, BigDecimal(0)].max
      end

      def charge_model_result
        @charge_model_result ||= ChargeModels::Factory.new_instance(
          pricing_structure: ChargeModels::PricingStructure.from_billing_cycle(billing_cycle),
          aggregation_result:,
          period_ratio: billing_cycle.proration_ratio,
          calculate_projected_usage: false
        ).apply
      end

      # The amount comes from the weighted quantity; the tier comes from the closing one.
      # That split is what the volume model expects (its range is selected by
      # full_units_number) and it matches the legacy engine.
      def aggregation_result
        prorated_units = billable_units * billing_cycle.proration_ratio

        BillableMetrics::Aggregations::BaseService::Result.new.tap do |aggregation_result|
          aggregation_result.aggregation = prorated_units
          aggregation_result.current_usage_units = prorated_units
          aggregation_result.full_units_number = units
          aggregation_result.count = 1
          aggregation_result.precise_total_amount_cents = 0
          aggregation_result.options = {running_total: []}
        end
      end
    end
  end
end
