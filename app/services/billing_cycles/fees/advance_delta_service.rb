# frozen_string_literal: true

module BillingCycles
  module Fees
    # Prices an increase on a pay-in-advance card: what is owed for raising the quantity
    # part-way through a period that has already been invoiced.
    #
    # Billable units are measured against the WATERMARK — the highest quantity already paid
    # for this period — not against the previous quantity. Decreases never refund, so that
    # coverage stays paid until the period ends: going 5 -> 2 -> 7 must bill units 6-7 only.
    #
    # The amount is the difference between two full prices rather than the price of the delta:
    #
    #   amount = model(new x ratio) - model(watermark x ratio)
    #
    # Pricing the delta on its own would restart the tiers at position 1 and undercharge every
    # unit that actually sits high in the stack. On the legacy engine that is exactly what
    # happens: raising 3 -> 7 bills 4 units at the tier-1 rate ($134.00) where the correct
    # amount is $196.00, because units 6-7 belong in tier 2. Taking the difference prices each
    # unit at the tier it occupies, and the flat fee of a newly reached tier falls out of the
    # subtraction on its own — the tiers already paid for cancel.
    #
    # The formula holds for the combinations that can exist. Standard is linear, so scaling
    # the quantity and scaling the price agree. Graduated is only ever reached with ratio 1,
    # because graduated + advance + proration is rejected at configuration time by both
    # engines (RateCardRates::ModelCompatibility, FixedCharge#validate_prorated).
    class AdvanceDeltaService < BaseService
      Result = BaseResult[:amount, :billable_units]

      def initialize(billing_cycle:, units:, already_billed_units:)
        @billing_cycle = billing_cycle
        @units = BigDecimal(units.to_s)
        @already_billed_units = BigDecimal(already_billed_units.to_s)
        super
      end

      def call
        result.billable_units = billable_units

        result.amount = if billable_units.zero?
          BigDecimal(0)
        else
          price_for(units) - price_for(already_billed_units)
        end

        result
      end

      private

      attr_reader :billing_cycle, :units, :already_billed_units

      # A decrease bills nothing and leaves the watermark where it is.
      def billable_units
        @billable_units ||= [units - already_billed_units, BigDecimal(0)].max
      end

      def price_for(quantity)
        ChargeModels::Factory.new_instance(
          pricing_structure: ChargeModels::PricingStructure.from_billing_cycle(billing_cycle),
          aggregation_result: aggregation_for(quantity),
          period_ratio: proration_ratio,
          calculate_projected_usage: false
        ).apply.amount
      end

      def aggregation_for(quantity)
        scaled = quantity * proration_ratio

        BillableMetrics::Aggregations::BaseService::Result.new.tap do |aggregation_result|
          aggregation_result.aggregation = scaled
          aggregation_result.current_usage_units = scaled
          aggregation_result.full_units_number = quantity
          aggregation_result.count = 1
          aggregation_result.precise_total_amount_cents = 0
          aggregation_result.options = {running_total: []}
        end
      end

      # The share of the period still ahead of the change: the customer already paid for the
      # days behind it at the old quantity.
      def proration_ratio
        billing_cycle.proration_ratio
      end
    end
  end
end
