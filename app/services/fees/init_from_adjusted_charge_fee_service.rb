# frozen_string_literal: true

module Fees
  class InitFromAdjustedChargeFeeService < ::BaseService
    Result = BaseResult[:fee]

    def initialize(adjusted_fee:, boundaries:, properties:)
      @adjusted_fee = adjusted_fee
      @boundaries = boundaries
      @properties = properties

      super
    end

    def call
      if adjusted_fee.adjusted_units? && amount_result.failure?
        return result.fail_with_error!(amount_result.error)
      end

      result.fee = init_adjusted_fee
      result
    end

    private

    attr_reader :adjusted_fee, :boundaries, :properties

    delegate :charge, :charge_filter, :invoice, :subscription, to: :adjusted_fee

    def init_adjusted_fee
      currency = invoice.total_amount.currency
      units = adjusted_fee.units
      amount_details = adjusted_fee.adjusted_units? ? amount_result.amount_details : {}

      if charge.applied_pricing_unit
        amount_cents, precise_amount_cents, unit_amount_cents, precise_unit_amount = pricing_unit_usage
          .to_fiat_currency_cents(currency)
          .values_at(:amount_cents, :precise_amount_cents, :unit_amount_cents, :precise_unit_amount)
      elsif adjusted_fee.adjusted_units?
        rounded_amount = amount_result.amount.round(currency.exponent)
        precise_amount_cents = amount_result.amount * currency.subunit_to_unit.to_d
        amount_cents = rounded_amount * currency.subunit_to_unit
        unit_amount_cents = amount_result.unit_amount * currency.subunit_to_unit
        precise_unit_amount = amount_result.unit_amount
      else
        unit_precise_amount_cents = adjusted_fee.unit_precise_amount_cents
        unit_amount_cents = unit_precise_amount_cents.round
        precise_amount_cents = units * unit_precise_amount_cents
        amount_cents = precise_amount_cents.round
        precise_unit_amount = unit_precise_amount_cents / currency.subunit_to_unit
      end

      Fee.new(
        invoice:,
        organization_id: invoice.organization_id,
        billing_entity_id: invoice.billing_entity_id,
        subscription:,
        charge:,
        amount_cents:,
        precise_amount_cents:,
        amount_currency: currency,
        fee_type: :charge,
        invoiceable_type: "Charge",
        invoiceable: charge,
        units:,
        total_aggregated_units: units,
        properties: boundaries.to_h,
        events_count: 0,
        payment_status: :pending,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        unit_amount_cents:,
        precise_unit_amount:,
        amount_details:,
        invoice_display_name: adjusted_fee.invoice_display_name,
        grouped_by: adjusted_fee.grouped_by,
        charge_filter_id: charge_filter&.id,
        pricing_unit_usage:
      )
    end

    def amount_result
      return @amount_result if defined?(@amount_result)

      aggregation_result = BaseService::Result.new
      aggregation_result.aggregation = adjusted_fee.units
      aggregation_result.current_usage_units = adjusted_fee.units
      aggregation_result.full_units_number = adjusted_fee.units
      aggregation_result.count = 0

      if charge.dynamic?
        aggregation_result.precise_total_amount_cents = 0
      end

      @amount_result = Charges::ChargeModelFactory
        .new_instance(charge:, aggregation_result:, properties:)
        .apply
    end

    def pricing_unit_usage
      return @pricing_unit_usage if defined?(@pricing_unit_usage)

      unless charge.applied_pricing_unit
        @pricing_unit_usage = nil
        return
      end

      @pricing_unit_usage = if adjusted_fee.adjusted_units?
        PricingUnitUsage.build_from_aggregation(amount_result, charge.applied_pricing_unit)
      else
        unit_precise_amount_cents = adjusted_fee.unit_precise_amount_cents
        precise_amount_cents = adjusted_fee.units * unit_precise_amount_cents

        PricingUnitUsage.new(
          pricing_unit: charge.pricing_unit,
          short_name: charge.pricing_unit.short_name,
          conversion_rate: charge.applied_pricing_unit.conversion_rate,
          amount_cents: precise_amount_cents.round,
          precise_amount_cents:,
          unit_amount_cents: unit_precise_amount_cents.round
        )
      end
    end
  end
end
