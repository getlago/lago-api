# frozen_string_literal: true

module Fees
  class AmountsService < BaseService
    Result = BaseResult[:amount, :true_up_amount]
    Amount = Data.define(
      :amount_cents,
      :precise_amount_cents,
      :unit_amount_cents,
      :precise_unit_amount,
      :pricing_unit_usage
    ) do
      def with_deduction(deduction)
        with(
          amount_cents: [amount_cents - deduction, 0].max,
          precise_amount_cents: [precise_amount_cents - deduction.to_d, 0.to_d].max
        )
      end
    end
    private_constant :Amount

    Deduction = Data.define(:amount_cents, :billed_days, :period_days) do
      def self.none
        new(amount_cents: nil, billed_days: 1, period_days: 1)
      end

      def none?
        amount_cents.nil?
      end

      def prorated_amount_cents
        (amount_cents * billed_days.to_f / period_days).round
      end
    end

    TrueUp = Data.define(:minimum_amount_cents, :billed_days, :period_days, :used_amount_cents, :used_precise_amount_cents) do
      def self.none
        new(minimum_amount_cents: nil)
      end

      def initialize(minimum_amount_cents:, billed_days: 1, period_days: 1, used_amount_cents: nil, used_precise_amount_cents: nil)
        super
      end

      def none?
        minimum_amount_cents.nil?
      end

      def prorated_minimum_amount_cents
        minimum_amount_cents.fdiv(period_days) * billed_days
      end
    end

    AppliedPricingUnit = Data.define(:pricing_unit, :conversion_rate) do
      def self.none
        new(pricing_unit: nil, conversion_rate: nil)
      end

      def self.from_pricing_unit(pricing_unit:, conversion_rate:)
        if pricing_unit.nil?
          none
        else
          new(pricing_unit:, conversion_rate:)
        end
      end

      def self.from_applied_pricing_unit(applied_pricing_unit)
        if applied_pricing_unit.nil?
          none
        else
          from_pricing_unit(pricing_unit: applied_pricing_unit.pricing_unit, conversion_rate: applied_pricing_unit.conversion_rate)
        end
      end

      def none?
        pricing_unit.nil?
      end

      def subunit_to_unit
        pricing_unit.subunit_to_unit.to_d
      end
    end

    def initialize(
      currency:,
      charge_model_result:,
      applied_pricing_unit: AppliedPricingUnit.none,
      deduction: Deduction.none,
      true_up: TrueUp.none
    )
      unless charge_model_result.is_a?(ChargeModels::BaseService::Result) ||
          charge_model_result.is_a?(Charges::ApplyPayInAdvanceChargeModelService::Result)
        raise ArgumentError, "charge_model_result must be a ChargeModels::BaseService::Result or Charges::ApplyPayInAdvanceChargeModelService::Result"
      end

      @currency = currency
      @charge_model_result = charge_model_result
      @applied_pricing_unit = applied_pricing_unit
      @deduction = deduction
      @true_up = true_up
      super
    end

    def call
      # An empty model result means no base fee, not a zero-valued fee.
      unless charge_model_result.amount.nil?
        result.amount = if charge_model_result.is_a?(Charges::ApplyPayInAdvanceChargeModelService::Result)
          advance_amount
        elsif charge_model_result.units.negative? || charge_model_result.amount.negative?
          build_amount(amount: 0.to_d, unit_amount: 0.to_d)
        else
          build_amount(amount: charge_model_result.amount, unit_amount: charge_model_result.unit_amount)
        end
        unless deduction.none?
          result.amount = result.amount.with_deduction(deduction.prorated_amount_cents)
        end
      end

      result.true_up_amount = true_up_amount
      result
    end

    private

    attr_reader :currency, :charge_model_result, :applied_pricing_unit, :deduction, :true_up

    def advance_amount
      if !applied_pricing_unit.none?
        build_amount(
          amount: charge_model_result.amount / applied_pricing_unit.subunit_to_unit,
          unit_amount: charge_model_result.unit_amount
        )
      else
        # Advance totals are already in minor units, with independently computed precision.
        Amount.new(
          amount_cents: charge_model_result.amount,
          precise_amount_cents: charge_model_result.precise_amount,
          unit_amount_cents: charge_model_result.unit_amount * currency.subunit_to_unit,
          precise_unit_amount: charge_model_result.unit_amount,
          pricing_unit_usage: nil
        )
      end
    end

    def true_up_amount
      return if true_up.none?

      minimum = true_up.prorated_minimum_amount_cents
      usage = result.amount&.pricing_unit_usage || result.amount
      used = true_up.used_amount_cents || usage.amount_cents
      precise_used = true_up.used_precise_amount_cents || usage.precise_amount_cents
      return if used >= minimum

      difference = minimum - used
      precise_difference = minimum - precise_used

      if !applied_pricing_unit.none?
        # Minimum and used totals are in pricing-unit cents, not fiat cents.
        subunit = applied_pricing_unit.subunit_to_unit
        build_amount(amount: difference / subunit, unit_amount: precise_difference / subunit)
      else
        # True-ups retain separate rounded and precise totals across grouped fees.
        Amount.new(
          amount_cents: difference.round,
          precise_amount_cents: precise_difference,
          unit_amount_cents: difference.round,
          precise_unit_amount: precise_difference / currency.subunit_to_unit,
          pricing_unit_usage: nil
        )
      end
    end

    def build_amount(amount:, unit_amount:)
      attributes = if !applied_pricing_unit.none?
        usage = PricingUnitUsage.build_from_fiat_amounts(amount:, unit_amount:, applied_pricing_unit:)
        usage.to_fiat_currency_cents(currency).merge(pricing_unit_usage: usage)
      else
        {
          amount_cents: amount.round(currency.exponent) * currency.subunit_to_unit,
          precise_amount_cents: amount * currency.subunit_to_unit.to_d,
          unit_amount_cents: unit_amount * currency.subunit_to_unit,
          precise_unit_amount: unit_amount,
          pricing_unit_usage: nil
        }
      end

      Amount.new(
        amount_cents: attributes.fetch(:amount_cents),
        precise_amount_cents: attributes.fetch(:precise_amount_cents),
        unit_amount_cents: attributes.fetch(:unit_amount_cents),
        precise_unit_amount: attributes.fetch(:precise_unit_amount),
        pricing_unit_usage: attributes.fetch(:pricing_unit_usage)
      )
    end
  end
end
