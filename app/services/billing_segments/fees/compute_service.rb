# frozen_string_literal: true

module BillingSegments
  module Fees
    class ComputeService < BaseService
      Result = BaseResult[:fee, :true_up_fee]

      def initialize(billing_segment:)
        @billing_segment = billing_segment
        super
      end

      def call
        return result.not_found_failure!(resource: "rate") unless rate

        result.fee = fee
        result.true_up_fee = true_up_fee
        result
      end

      private

      attr_reader :billing_segment

      delegate :rate, :rate_card_rate, :rate_override, :contract_rate_card, to: :billing_segment
      delegate :product, to: :contract_rate_card

      def fee
        @fee ||= Fee.new(
          organization: billing_segment.organization,
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
          properties: boundaries.to_h.merge("billing_segment_id" => billing_segment.id)
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
        @fee_amounts ||= ::Fees::AmountsService.call!(
          currency:,
          charge_model_result:,
          applied_pricing_unit:,
          true_up: ::Fees::AmountsService::TrueUp.new(minimum_amount_cents: billing_segment.prorated_min_amount_cents)
        )
      end

      def currency
        @currency ||= Money::Currency.new(billing_segment.currency)
      end

      def applied_pricing_unit
        ::Fees::AmountsService::AppliedPricingUnit.from_pricing_unit(
          pricing_unit: billing_segment.pricing_unit,
          conversion_rate: billing_segment.pricing_unit_conversion_rate
        )
      end

      def units
        contract_rate_card.units || BigDecimal(0)
      end

      def charge_model_result
        @charge_model_result ||= ChargeModels::Factory.new_instance(
          pricing_structure: ChargeModels::PricingStructure.from_billing_segment(billing_segment),
          aggregation_result:,
          period_ratio: billing_segment.elapsed_period_ratio,
          calculate_projected_usage: false
        ).apply
      end

      def boundaries
        BillingPeriodBoundaries.new(
          from_datetime: billing_segment.started_at,
          to_datetime: billing_segment.ended_at,
          charges_from_datetime: billing_segment.started_at,
          charges_to_datetime: billing_segment.ended_at,
          charges_duration: billing_segment.duration_in_days,
          timestamp: billing_segment.billing_at
        )
      end

      def aggregation_result
        prorated_units = units * billing_segment.proration_ratio
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
