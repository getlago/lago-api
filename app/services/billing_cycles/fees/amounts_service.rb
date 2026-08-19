# frozen_string_literal: true

module BillingCycles
  module Fees
    class AmountsService < BaseService
      Result = BaseResult[
        :amount_cents,
        :precise_amount_cents,
        :unit_amount_cents,
        :precise_unit_amount,
        :pricing_unit_usage
      ]

      def initialize(billing_cycle:, charge_model_result:, currency:, units:)
        @billing_cycle = billing_cycle
        @charge_model_result = charge_model_result
        @currency = currency
        @units = units
        super
      end

      def call
        result.amount_cents = amounts.amount_cents
        result.precise_amount_cents = amounts.precise_amount_cents
        result.unit_amount_cents = amounts.unit_amount_cents
        result.precise_unit_amount = amounts.precise_unit_amount
        result.pricing_unit_usage = amounts.pricing_unit_usage
        result
      end

      private

      attr_reader :billing_cycle, :charge_model_result, :currency, :units

      def amounts
        @amounts ||= Amounts.build(
          billing_cycle:,
          charge_model_result:,
          currency:,
          units:
        )
      end

      class Amounts
        def self.build(billing_cycle:, charge_model_result:, currency:, units:)
          if billing_cycle.pricing_unit
            return WithPricingUnit.new(billing_cycle:, charge_model_result:, currency:, units:)
          end

          new(charge_model_result:, currency:, units:)
        end

        def initialize(charge_model_result:, currency:, units:)
          @charge_model_result = charge_model_result
          @currency = currency
          @units = units
        end

        def amount_cents
          @amount_cents ||= (charge_model_result.amount.round(currency.exponent) * subunit).round
        end

        def precise_amount_cents
          BigDecimal(amount_cents)
        end

        def unit_amount_cents
          return 0 if units.zero?

          (amount_cents / units).round
        end

        def precise_unit_amount
          return BigDecimal(0) if units.zero?

          BigDecimal(amount_cents) / units / subunit
        end

        def pricing_unit_usage
          nil
        end

        private

        attr_reader :charge_model_result, :currency, :units

        def subunit
          currency.subunit_to_unit
        end
      end

      class WithPricingUnit < Amounts
        def initialize(billing_cycle:, charge_model_result:, currency:, units:)
          @billing_cycle = billing_cycle
          super(charge_model_result:, currency:, units:)
        end

        def amount_cents
          fiat_amounts[:amount_cents]
        end

        def precise_amount_cents
          fiat_amounts[:precise_amount_cents]
        end

        def unit_amount_cents
          return 0 if units.zero?

          fiat_amounts[:unit_amount_cents]
        end

        def precise_unit_amount
          return BigDecimal(0) if units.zero?

          fiat_amounts[:precise_unit_amount]
        end

        def pricing_unit_usage
          @pricing_unit_usage ||= PricingUnitUsage.build_from_fiat_amounts(
            amount: charge_model_result.amount,
            unit_amount: charge_model_result.unit_amount,
            applied_pricing_unit:
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

        def fiat_amounts
          @fiat_amounts ||= pricing_unit_usage.to_fiat_currency_cents(currency)
        end
      end

      private_constant :Amounts, :WithPricingUnit
    end
  end
end
