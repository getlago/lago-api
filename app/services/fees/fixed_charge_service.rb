# frozen_string_literal: true

module Fees
  class FixedChargeService < BaseService
    Result = BaseResult[:fees]

    def initialize(invoice:, fixed_charge:, subscription:, boundaries:, context: nil)
      @invoice = invoice
      @fixed_charge = fixed_charge
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)
      @currency = subscription.plan.amount.currency
      @context = context

      super
    end

    def call
      return result if already_billed?

      init_fees
      return result unless result.success?

      ActiveRecord::Base.transaction do
        result.fees.each do |fee|
          fee.save!
        end
      end

      result
    end

    private

    attr_accessor :invoice, :fixed_charge, :subscription, :boundaries, :context, :currency

    def already_billed?
      invoice.fees.fixed_charge.where(fixed_charge:).exists?
    end

    def init_fees
      result.fees = []

      units = subscription.units_override_for(fixed_charge) || fixed_charge.units
      return result if units.zero?

      aggregation_result = BaseService::Result.new
      aggregation_result.aggregation = units
      aggregation_result.current_usage_units = units
      aggregation_result.full_units_number = units
      aggregation_result.count = 1

      charge_model_result = FixedCharges::ChargeModelFactory.new_instance(
        fixed_charge:,
        aggregation_result:,
        properties: fixed_charge.properties
      ).apply

      rounded_amount = charge_model_result.amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit
      precise_amount_cents = charge_model_result.amount * currency.subunit_to_unit.to_d
      unit_amount_cents = charge_model_result.unit_amount * currency.subunit_to_unit

      fee = Fee.new(
        subscription:,
        fixed_charge:,
        organization_id: subscription.organization_id,
        billing_entity_id: subscription.billing_entity_id,
        amount_cents:,
        precise_amount_cents:,
        amount_currency: currency.iso_code,
        fee_type: :fixed_charge,
        invoiceable: fixed_charge,
        units: charge_model_result.units,
        total_aggregated_units: charge_model_result.units,
        properties: boundaries.to_h,
        events_count: charge_model_result.count,
        payment_status: :pending,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        unit_amount_cents:,
        precise_unit_amount: charge_model_result.unit_amount,
        grouped_by: {},
        amount_details: charge_model_result.amount_details || {}
      )

      result.fees << fee
    end
  end
end