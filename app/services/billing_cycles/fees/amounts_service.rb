# frozen_string_literal: true

module BillingCycles
  module Fees
    class AmountsService < BaseService
      Result = BaseResult[:amount, :true_up_amount]
      Amount = Data.define(
        :amount_cents,
        :precise_amount_cents,
        :unit_amount_cents,
        :precise_unit_amount,
        :pricing_unit_usage
      )

      def initialize(billing_cycle:, charge_model_result:, currency:, units:)
        @billing_cycle = billing_cycle
        @charge_model_result = charge_model_result
        @currency = currency
        @units = units
        super
      end

      def call
        result.amount = amount
        result.true_up_amount = true_up_amount
        result
      end

      private

      attr_reader :billing_cycle, :charge_model_result, :currency, :units

      def amount
        @amount ||= amounts.amount_for(charge_model_result:, units:)
      end

      def true_up_amount
        return if minimum_amount_cents.to_i.zero?
        return if amount.amount_cents >= minimum_amount_cents

        amounts.amount_for(charge_model_result: true_up_amount_result, units: 1)
      end

      def true_up_amount_result
        BaseResult[:amount, :unit_amount].new.tap do |result|
          result.amount = true_up_amount_units
          result.unit_amount = true_up_amount_units
        end
      end

      def true_up_amount_units
        if billing_cycle.pricing_unit
          return true_up_currency_amount / billing_cycle.pricing_unit_conversion_rate
        end

        true_up_currency_amount
      end

      def true_up_currency_amount
        (minimum_amount_cents - amount.amount_cents).to_d / currency.subunit_to_unit
      end

      def minimum_amount_cents
        (billing_cycle.min_amount_cents * billing_cycle.proration_ratio).round
      end

      def amounts
        @amounts ||= Amounts.build(
          billing_cycle:,
          currency:
        )
      end

      class Amounts
        def self.build(billing_cycle:, currency:)
          if billing_cycle.pricing_unit
            return WithPricingUnit.new(billing_cycle:, currency:)
          end

          new(currency:)
        end

        def initialize(currency:)
          @currency = currency
        end

        def amount_for(charge_model_result:, units:)
          amount_cents = amount_cents_for(charge_model_result)
          Amount.new(
            amount_cents:,
            precise_amount_cents: BigDecimal(amount_cents),
            unit_amount_cents: unit_amount_cents_for(amount_cents, units),
            precise_unit_amount: precise_unit_amount_for(amount_cents, units),
            pricing_unit_usage: nil
          )
        end

        private

        attr_reader :currency

        def amount_cents_for(charge_model_result)
          (charge_model_result.amount.round(currency.exponent) * subunit).round
        end

        def unit_amount_cents_for(amount_cents, units)
          return 0 if units.zero?

          (amount_cents / units).round
        end

        def precise_unit_amount_for(amount_cents, units)
          return BigDecimal(0) if units.zero?

          BigDecimal(amount_cents) / units / subunit
        end

        def subunit
          currency.subunit_to_unit
        end
      end

      class WithPricingUnit < Amounts
        def initialize(billing_cycle:, currency:)
          @billing_cycle = billing_cycle
          super(currency:)
        end

        def amount_for(charge_model_result:, units:)
          pricing_unit_usage = pricing_unit_usage_for(charge_model_result)
          fiat_amounts = pricing_unit_usage.to_fiat_currency_cents(currency)

          Amount.new(
            amount_cents: fiat_amounts[:amount_cents],
            precise_amount_cents: fiat_amounts[:precise_amount_cents],
            unit_amount_cents: unit_amount_cents_for(fiat_amounts, units),
            precise_unit_amount: precise_unit_amount_for(fiat_amounts, units),
            pricing_unit_usage:
          )
        end

        private

        attr_reader :billing_cycle

        def applied_pricing_unit
          AppliedPricingUnit.new(
            organization: billing_cycle.organization,
            pricing_unit: billing_cycle.pricing_unit,
            conversion_rate: billing_cycle.pricing_unit_conversion_rate
          )
        end

        def pricing_unit_usage_for(charge_model_result)
          PricingUnitUsage.build_from_fiat_amounts(
            amount: charge_model_result.amount,
            unit_amount: charge_model_result.unit_amount,
            applied_pricing_unit:
          )
        end

        def unit_amount_cents_for(fiat_amounts, units)
          return 0 if units.zero?

          fiat_amounts[:unit_amount_cents]
        end

        def precise_unit_amount_for(fiat_amounts, units)
          return BigDecimal(0) if units.zero?

          fiat_amounts[:precise_unit_amount]
        end
      end

      private_constant :Amounts, :WithPricingUnit
    end
  end
end
