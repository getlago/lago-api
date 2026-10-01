# frozen_string_literal: true

module Fees
  class ProjectionService < ::BaseService
    Result = BaseResult[:projection]

    # These charge models price the projected units with the charge properties. The others
    # depend on per-event data the fee does not keep, so their current amount is scaled instead.
    REPRICED_CHARGE_MODELS = %w[standard graduated package volume].freeze

    UnitsAggregationResult = Struct.new(
      :grouped_by, :aggregator, :aggregations, :aggregation, :total_aggregated_units,
      :current_usage_units, :full_units_number, :count, :options,
      keyword_init: true
    )

    def initialize(fee:, timezone:)
      @fee = fee
      @timezone = timezone

      super(nil)
    end

    def call
      result.projection = if charge.billable_metric.recurring?
        current_projection
      elsif period_ratio.positive?
        projection
      else
        UsageProjection.zero(pricing_unit_amount_cents: charge.applied_pricing_unit ? 0 : nil)
      end

      result
    end

    private

    attr_reader :fee, :timezone

    delegate :charge, :charge_filter, to: :fee

    def current_projection
      UsageProjection.new(
        units: units,
        amount_cents: fee.amount_cents,
        pricing_unit_amount_cents: fee.pricing_unit_usage&.amount_cents,
        presentation_breakdowns: fee.presentation_breakdowns.to_a
      )
    end

    def projection
      amount_cents, pricing_unit_amount_cents = repriced? ? repriced_amounts : scaled_amounts

      UsageProjection.new(
        units: projected_units,
        amount_cents:,
        pricing_unit_amount_cents:,
        presentation_breakdowns: projected_presentation_breakdowns
      )
    end

    # Prorated charges only exist on recurring metrics, which are never extrapolated.
    def repriced?
      REPRICED_CHARGE_MODELS.include?(charge.charge_model)
    end

    def repriced_amounts
      charge_model_result = ChargeModels::Factory.new_instance(
        pricing_structure: ChargeModels::PricingStructure.from_charge(charge).with(properties: properties_for_charge_model),
        aggregation_result: units_aggregation_result,
        period_ratio:,
        calculate_projected_usage: true
      ).apply.raise_if_error!
      return [0, charge.applied_pricing_unit ? 0 : nil] if charge_model_result.projected_amount.nil?

      projected_result = ChargeModels::BaseService::Result.new.tap do |projected|
        projected.units = charge_model_result.projected_units
        projected.amount = charge_model_result.projected_amount
        projected.unit_amount = charge_model_result.unit_amount
      end

      amount = Fees::AmountsService.call!(
        currency:,
        charge_model_result: projected_result,
        applied_pricing_unit: Fees::AmountsService::AppliedPricingUnit.from_applied_pricing_unit(charge.applied_pricing_unit)
      ).amount

      [amount.amount_cents, amount.pricing_unit_usage&.amount_cents]
    end

    def scaled_amounts
      [
        scale(fee.precise_amount_cents),
        fee.pricing_unit_usage&.then { |usage| scale(usage.precise_amount_cents) }
      ]
    end

    def scale(precise_amount_cents)
      [(precise_amount_cents.to_d / period_ratio.to_d).round, 0].max
    end

    def units_aggregation_result
      UnitsAggregationResult.new(
        aggregation: units,
        total_aggregated_units: units,
        current_usage_units: units,
        full_units_number: units,
        count: fee.events_count.to_i,
        options: {running_total: []}
      )
    end

    def units
      @units ||= BigDecimal(fee.units.to_s)
    end

    def projected_units
      return BigDecimal(0) unless units.positive?

      (units / period_ratio.to_d).round(2)
    end

    def projected_presentation_breakdowns
      fee.presentation_breakdowns.map do |breakdown|
        breakdown.dup.tap do |projected|
          projected.units = (BigDecimal(breakdown.units.to_s) / period_ratio.to_d).round(currency.exponent)
        end
      end
    end

    def properties_for_charge_model
      charge_filter&.properties.presence || charge.properties
    end

    def currency
      fee.amount.currency
    end

    def period_ratio
      return @period_ratio if defined?(@period_ratio)

      from_datetime = Time.zone.parse(fee.properties["from_datetime"].to_s)
      to_datetime = Time.zone.parse(fee.properties["to_datetime"].to_s)
      current_time = Time.current

      return @period_ratio = 1.0 if current_time >= to_datetime
      return @period_ratio = 0.0 if current_time < from_datetime

      total_days = Utils::Datetime.date_diff_with_timezone(from_datetime, to_datetime, timezone)
      days_passed = Utils::Datetime.date_diff_with_timezone(from_datetime, current_time, timezone)

      @period_ratio = days_passed.fdiv(total_days).clamp(0.0, 1.0)
    end
  end
end
