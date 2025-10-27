# frozen_string_literal: true

module Fees
  class FixedChargeService < BaseService
    Result = BaseResult[:fee]

    def initialize(
      invoice:,
      fixed_charge:,
      subscription:,
      boundaries:,
      apply_taxes: false,
      context: nil
    )
      @invoice = invoice
      @fixed_charge = fixed_charge
      @subscription = subscription
      @organization = subscription.organization
      @boundaries = readjust_boundaries(boundaries)
      @currency = subscription.plan.amount.currency
      @apply_taxes = apply_taxes
      @context = context
      @current_usage = context == :current_usage

      super(nil)
    end

    def call
      return result if already_billed?

      init_fee
      return result if current_usage

      result.fee.save! if context != :invoice_preview && should_persist_fee?
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :fixed_charge, :subscription, :boundaries, :apply_taxes, :context, :current_usage, :currency, :organization

    def already_billed?
      invoice.fees.fixed_charge.exists?(fixed_charge_id: fixed_charge.id)
    end

    def init_fee
      amount_result = apply_aggregation_and_charge_model

      # Prevent trying to create a fee with negative units or amount.
      if amount_result.units.negative? || amount_result.amount.negative?
        amount_result.amount = amount_result.unit_amount = BigDecimal(0)
        amount_result.full_units_number = amount_result.units = amount_result.total_aggregated_units = BigDecimal(0)
      end

      # TODO: add pricing units
      pricing_unit_usage = nil
      rounded_amount = amount_result.amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit
      precise_amount_cents = amount_result.amount * currency.subunit_to_unit.to_d
      unit_amount_cents = amount_result.unit_amount * currency.subunit_to_unit
      precise_unit_amount = amount_result.unit_amount

      units = amount_result.full_units_number

      if first_prorated_paid_in_advance_charge_billed_in_prev_subscription?
        already_paid_fee = find_already_paid_fee_for_the_fixed_charge(boundaries)
        if already_paid_fee
          current_period_duration_days = ((boundaries[:fixed_charges_to_datetime] - boundaries[:fixed_charges_from_datetime]) / 1.day.in_seconds).ceil
          prorated_for_current_period = already_paid_fee.amount_cents * current_period_duration_days / boundaries[:fixed_charges_duration]
          amount_cents -= prorated_for_current_period
          precise_amount_cents -= prorated_for_current_period.to_d
          amount_cents = 0 if amount_cents < 0
          precise_amount_cents = 0 if precise_amount_cents < 0
        end
      end

      new_fee = Fee.new(
        invoice:,
        organization_id: organization.id,
        billing_entity_id: subscription.customer.billing_entity_id,
        subscription:,
        fixed_charge:,
        amount_cents:,
        precise_amount_cents:,
        amount_currency: currency,
        fee_type: :fixed_charge,
        invoiceable_type: "FixedCharge",
        invoiceable: fixed_charge,
        units:,
        total_aggregated_units: amount_result.total_aggregated_units || units,
        properties: boundaries.to_h,
        payment_status: :pending,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        unit_amount_cents:,
        precise_unit_amount:,
        amount_details: amount_result.amount_details,
        pricing_unit_usage:,
        pay_in_advance: fixed_charge.pay_in_advance?
      )

      if apply_taxes
        taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)
        taxes_result.raise_if_error!
      end

      result.fee = new_fee
    end

    def apply_aggregation_and_charge_model
      aggregation_result = aggregator.call

      ChargeModels::Factory.new_instance(
        chargeable: fixed_charge,
        aggregation_result:,
        properties: fixed_charge.properties,
        period_ratio: calculate_period_ratio,
        calculate_projected_usage: false
      ).apply
    end

    def aggregator
      if fixed_charge.prorated?
        return FixedChargeEvents::Aggregations::ProratedAggregationService.new(fixed_charge:, subscription:, boundaries:)
      end

      FixedChargeEvents::Aggregations::SimpleAggregationService.new(fixed_charge:, subscription:, boundaries:)
    end

    def calculate_period_ratio
      from_date = boundaries[:fixed_charges_from_datetime].to_date
      to_date = boundaries[:fixed_charges_to_datetime].to_date
      current_date = Time.current.to_date

      total_days = (to_date - from_date).to_i + 1
      charges_duration = boundaries[:fixed_charges_duration] || total_days

      return 1.0 if current_date >= to_date
      return 0.0 if current_date < from_date

      days_passed = (current_date - from_date).to_i + 1

      ratio = days_passed.fdiv(charges_duration)
      ratio.clamp(0.0, 1.0)
    end

    def should_persist_fee?
      return true if context == :recurring
      return true if organization.zero_amount_fees_enabled?
      return true if result.fee.units != 0 || result.fee.amount_cents != 0

      false
    end

    # Note: boundaries are taken from the subscription and they do not consider some fixed_charges being pay_in_advance
    def readjust_boundaries(boundaries)
      properties = boundaries.to_h
      properties["charges_from_datetime"] = nil
      properties["charges_to_datetime"] = nil
      properties["charges_duration"] = nil

      return properties if !fixed_charge.pay_in_advance?
      timestamp = boundaries.timestamp
      in_advance_dates = Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)

      properties["fixed_charges_from_datetime"] = in_advance_dates[:fixed_charges_from_datetime]
      properties["fixed_charges_to_datetime"] = in_advance_dates[:fixed_charges_to_datetime]
      properties["fixed_charges_duration"] = in_advance_dates[:fixed_charges_duration]
      properties
    end

    # if we have a prorated paid in advance fixed charge, and we're upgrading to a new plan with the same add_on,
    # there is an existing fee paid for the full month, but at the moment of upgrade, the new price should applied,
    # so we need to deduct the prorated for the rest of the billing period amount that was already paid from the new price.
    def first_prorated_paid_in_advance_charge_billed_in_prev_subscription?
      return false unless fixed_charge.pay_in_advance?
      return false unless fixed_charge.prorated?
      return false unless subscription.previous_subscription
      return false if subscription.invoices.count > 1
      fixed_charge.matching_fixed_charge_prev_subscription(subscription).present?
    end

    def find_already_paid_fee_for_the_fixed_charge(current_fee_boundaries)
      prev_fixed_charge = fixed_charge.matching_fixed_charge_prev_subscription(subscription)
      Fee.where(
        organization: organization,
        billing_entity: subscription.customer.billing_entity,
        fixed_charge: prev_fixed_charge
      ).where(
        "properties->>'fixed_charges_from_datetime' <= ? AND properties->>'fixed_charges_to_datetime' >= ?",
        current_fee_boundaries[:fixed_charges_from_datetime],
        current_fee_boundaries[:fixed_charges_to_datetime]
      ).first
    end
  end
end
