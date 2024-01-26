# frozen_string_literal: true

module Fees
  class InitFromAdjustedChargeFeeService < ::BaseService
    def initialize(adjusted_fee:, boundaries:, properties:)
      @adjusted_fee = adjusted_fee
      @boundaries = boundaries
      @properties = properties

      super
    end

    def call
      amount_result = compute_amount
      return result.fail_with_error!(amount_result.error) unless amount_result.success?

      result.fee = init_adjusted_fee(amount_result)
      result
    end

    private

    attr_reader :adjusted_fee, :boundaries, :properties

    delegate :group, :charge, :invoice, :subscription, to: :adjusted_fee

    def compute_amount
      adjusted_fee_result = BaseService::Result.new
      return adjusted_fee_result if adjusted_fee.adjusted_amount?

      adjusted_fee_result.aggregation = adjusted_fee.units
      adjusted_fee_result.current_usage_units = adjusted_fee.units
      adjusted_fee_result.full_units_number = adjusted_fee.units
      adjusted_fee_result.count = 0

      apply_charge_model_service(adjusted_fee_result)
    end

    def apply_charge_model_service(aggregation_result)
      Charges::ChargeModelFactory.new_instance(charge:, aggregation_result:, properties:).apply
    end

    def init_adjusted_fee(amount_result)
      currency = invoice.total_amount.currency

      units = adjusted_fee.units
      if adjusted_fee.adjusted_units?
        rounded_amount = amount_result.amount.round(currency.exponent)
        amount_cents = rounded_amount * currency.subunit_to_unit
        unit_amount_cents = amount_result.unit_amount * currency.subunit_to_unit
        precise_unit_amount = amount_result.unit_amount
        amount_details = amount_result.amount_details
      else
        unit_amount_cents = adjusted_fee.unit_amount_cents.round
        amount_cents = (units * unit_amount_cents).round
        precise_unit_amount = amount_cents / (currency.subunit_to_unit * units)
        amount_details = {}
      end

      Fee.new(
        invoice:,
        subscription:,
        charge:,
        amount_cents:,
        amount_currency: currency,
        fee_type: :charge,
        invoiceable_type: 'Charge',
        invoiceable: charge,
        units:,
        total_aggregated_units: units,
        properties: boundaries.to_h,
        events_count: 0,
        group_id: group&.id,
        payment_status: :pending,
        taxes_amount_cents: 0,
        unit_amount_cents:,
        precise_unit_amount:,
        amount_details:,
        invoice_display_name: adjusted_fee.invoice_display_name,
        grouped_by: adjusted_fee.grouped_by,
      )
    end
  end
end
