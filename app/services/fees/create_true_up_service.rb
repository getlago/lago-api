# frozen_string_literal: true

module Fees
  class CreateTrueUpService < BaseService
    Result = BaseResult[:true_up_fee]

    def initialize(fee:, used_amount_cents:, used_precise_amount_cents:)
      @fee = fee
      @used_amount_cents = used_amount_cents
      @used_precise_amount_cents = used_precise_amount_cents
      @boundaries = BillingPeriodBoundaries.from_fee(fee)

      super
    end

    def call
      return result unless fee
      amount = Fees::AmountsService.call(
        currency: charge.plan.amount.currency,
        charge_model_result: ChargeModels::BaseService::Result.new,
        applied_pricing_unit: Fees::AmountsService::AppliedPricingUnit.from_applied_pricing_unit(charge.applied_pricing_unit),
        true_up: Fees::AmountsService::TrueUp.new(
          minimum_amount_cents: charge.min_amount_cents,
          billed_days: subscription.date_diff_with_timezone(boundaries.charges_from_datetime.to_time, boundaries.charges_to_datetime.to_time),
          period_days: boundaries.charges_duration,
          used_amount_cents:,
          used_precise_amount_cents:
        )
      ).true_up_amount

      return result unless amount

      true_up_fee = fee.dup
      true_up_fee.assign_attributes(
        amount_cents: amount.amount_cents,
        precise_amount_cents: amount.precise_amount_cents,
        unit_amount_cents: amount.unit_amount_cents,
        precise_unit_amount: amount.precise_unit_amount,
        pricing_unit_usage: amount.pricing_unit_usage,
        units: 1,
        total_aggregated_units: 1,
        events_count: 0,
        charge_filter_id: nil,
        true_up_parent_fee: fee
      )

      result.true_up_fee = true_up_fee
      result
    end

    private

    attr_reader :fee, :used_amount_cents, :used_precise_amount_cents, :boundaries

    delegate :charge, :subscription, to: :fee
  end
end
