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
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :fixed_charge, :subscription, :boundaries, :context, :currency

    def init_fees
      result.fees = []

      # Use prorated aggregation service if the fixed charge is prorated
      aggregation_service = fixed_charge.prorated? ?
        FixedCharges::FixedChargesEvents::ProratedAggregationService :
        FixedCharges::FixedChargesEvents::AggregationService

      aggregation_result = aggregation_service.call(
        fixed_charge:,
        subscription:,
        boundaries: boundaries.to_h
      )

      return result if aggregation_result.aggregation.zero?

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
        fixed_charge:,
        invoice:,
        subscription:,
        organization_id: fixed_charge.organization_id,
        billing_entity_id: subscription.customer.billing_entity_id,
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

    def already_billed?
      existing_fees = if invoice
        invoice.fees.where(fixed_charge_id: fixed_charge.id, subscription_id: subscription.id)
      else
        Fee.where(
          fixed_charge_id: fixed_charge.id,
          subscription_id: subscription.id,
          invoice_id: nil,
          pay_in_advance_event_id: nil
        ).where(
          "(properties->>'charges_from_datetime')::timestamptz = ?", boundaries.charges_from_datetime&.iso8601(3)
        ).where(
          "(properties->>'charges_to_datetime')::timestamptz = ?", boundaries.charges_to_datetime&.iso8601(3)
        )
      end

      return false if existing_fees.blank?

      result.fees = existing_fees
      true
    end
  end
end
