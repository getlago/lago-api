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
    # Proration: when rate_card.proration is true, a partial period (a clamped first
    # period or a mid-period termination) is charged pro-rata by day count
    # (cycle_days / full_period_days). When false the full period amount is charged.
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
          units:,
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
        fee_amounts.amount
      end

      def true_up_amount
        fee_amounts.true_up_amount
      end

      def fee_amounts
        @fee_amounts ||= BillingCycles::Fees::AmountsService.call!(
          billing_cycle:,
          charge_model_result:,
          currency: Money::Currency.new(currency),
          units:,
          proration_ratio:
        )
      end

      def units
        subscription_rate_card.units || 0
      end

      def charge_model_result
        @charge_model_result ||= ChargeModels::Factory.new_instance(
          structure: ChargeModels::PricingStructure.from_billing_cycle(billing_cycle),
          aggregation_result:,
          period_ratio: proration_ratio,
          calculate_projected_usage: false
        ).apply
      end

      def aggregation_result
        prorated_units = units * proration_ratio

        BillableMetrics::Aggregations::BaseService::Result.new.tap do |aggregation_result|
          aggregation_result.aggregation = prorated_units
          aggregation_result.current_usage_units = prorated_units
          aggregation_result.full_units_number = units
          aggregation_result.count = 1
          aggregation_result.precise_total_amount_cents = 0
          aggregation_result.options = {running_total: []}
        end
      end

      # 1 for a full period; the prorated fraction for a partial period. The day math
      # lives on Boundaries (the billing calendar), matching the legacy engine.
      def proration_ratio
        return @proration_ratio if defined?(@proration_ratio)

        unless subscription_rate_card.proration?
          @proration_ratio = 1
          return @proration_ratio
        end

        boundaries = BillingPeriods::Boundaries.new(
          billing_anchor_date: subscription_rate_card.billing_anchor_date,
          interval_count: rate.billing_interval_count,
          interval_unit: rate.billing_interval_unit,
          timezone: subscription.customer.applicable_timezone
        )
        @proration_ratio = boundaries.proration_ratio(billing_cycle.period_from, billing_cycle.period_to)
      end
    end
  end
end
