# frozen_string_literal: true

module AdjustedFees
  class EstimateService < BaseService
    Result = BaseResult[:fee, :adjusted_fee]
    def initialize(invoice:, params:)
      @invoice = invoice
      @organization = invoice.organization
      @params = params

      super
    end

    def call
      fee = find_or_create_fee
      return result.not_found_failure!(resource: "fee") if fee.blank?

      charge = fee.charge
      return result.validation_failure!(errors: {charge: ["invalid_charge_model"]}) if disabled_charge_model?(charge)

      adjusted_fee = create_adjusted_fee(fee, charge, params)

      estimated_fee = if fee.fee_type == "subscription"
        adjust_subscription_fee(fee, adjusted_fee)
      else
        init_from_charge_fee(adjusted_fee)
      end

      apply_taxes_and_assign_ids(estimated_fee) unless customer.tax_customer
      result.fee = estimated_fee
      result
    end

    private

    attr_reader :organization, :invoice, :params

    def apply_taxes_and_assign_ids(fee)
      Fees::ApplyTaxesService.call!(fee:)
      fee.applied_taxes.each { |tax| tax.id = SecureRandom.uuid }
    end

    def init_from_charge_fee(adjusted_fee)
      properties = adjusted_fee.charge_filter&.properties || adjusted_fee.charge.properties

      result = Fees::InitFromAdjustedChargeFeeService.call(
        adjusted_fee:,
        boundaries: adjusted_fee.properties,
        properties:
      )

      result.fee.id = SecureRandom.uuid
      result.fee
    end

    def adjust_subscription_fee(fee, adjusted_fee)
      if adjusted_fee.adjusted_display_name?
        fee.invoice_display_name = adjusted_fee.invoice_display_name
        return fee
      end

      units = adjusted_fee.units
      subunit = invoice.total_amount.currency.subunit_to_unit

      if adjusted_fee.adjusted_units?
        unit_cents = fee.unit_amount_cents
        amount_cents = (units * unit_cents).round
        precise_unit_amount = unit_cents.to_f / subunit
      else
        unit_cents = adjusted_fee.unit_precise_amount_cents
        amount_cents = (units * unit_cents).round
        precise_unit_amount = unit_cents / subunit
      end

      fee.units = units
      fee.unit_amount_cents = unit_cents.round
      fee.precise_unit_amount = precise_unit_amount
      fee.amount_cents = amount_cents
      fee.precise_amount_cents = units * unit_cents
      fee.invoice_display_name = adjusted_fee.invoice_display_name if params[:invoice_display_name].present?

      fee
    end

    def create_adjusted_fee(fee, charge, params)
      unit_precise_amount_cents = if params[:unit_precise_amount].present?
        params[:unit_precise_amount].to_f * fee.amount.currency.subunit_to_unit
      else
        fee.precise_unit_amount
      end

      AdjustedFee.new(
        fee:,
        invoice: fee.invoice,
        subscription: fee.subscription,
        charge:,
        adjusted_units: params[:units].present? && params[:unit_precise_amount].blank?,
        adjusted_amount: params[:units].present? && params[:unit_precise_amount].present?,
        invoice_display_name: params[:invoice_display_name],
        fee_type: fee.fee_type,
        properties: fee.properties,
        units: params[:units].presence || 0,
        unit_amount_cents: unit_precise_amount_cents.round,
        unit_precise_amount_cents: unit_precise_amount_cents,
        grouped_by: fee.grouped_by,
        charge_filter: fee.charge_filter,
        organization:
      )
    end

    def disabled_charge_model?(charge)
      unit_adjustment = params[:units].present? && params[:unit_precise_amount].blank?

      charge && unit_adjustment && (charge.percentage? || (charge.prorated? && charge.graduated?))
    end

    def customer
      @customer ||= invoice.customer
    end

    def find_or_create_fee
      return find_existing_fee if params.key?(:fee_id)

      create_empty_fee
    end

    def find_existing_fee
      fee = invoice.fees.find_by(id: params[:fee_id])
      if fee.blank?
        result.not_found_failure!(resource: "fee")
        return
      end

      fee
    end

    def create_empty_fee
      subscription = invoice.subscriptions.includes(plan: {charges: :filters}).find_by(id: params[:invoice_subscription_id])
      unless subscription
        result.not_found_failure!(resource: "subscription")
        return
      end

      charge = subscription.plan.charges.find { |c| c.id == params[:charge_id] }
      unless charge
        result.not_found_failure!(resource: "charge")
        return
      end

      if params[:charge_filter_id].present?
        charge_filter = charge.filters.find_by(id: params[:charge_filter_id])

        unless charge_filter
          result.not_found_failure!(resource: "charge_filter")
          return
        end
      end

      fee = invoice.fees.find_by(
        subscription_id: subscription.id,
        charge_id: charge.id,
        charge_filter_id: params[:charge_filter_id]
      )
      fee || create_fee(subscription, charge)
    end

    def create_fee(subscription, charge)
      invoice_subscription = invoice.invoice_subscriptions.find_by(subscription_id: subscription.id)

      boundaries = {
        timestamp: invoice_subscription.timestamp,
        charges_from_datetime: invoice_subscription.charges_from_datetime,
        charges_to_datetime: invoice_subscription.charges_to_datetime
      }

      Fee.new(
        organization:,
        billing_entity_id: invoice.billing_entity_id,
        invoice:,
        subscription:,
        invoiceable: charge,
        charge:,
        charge_filter_id: params[:charge_filter_id],
        grouped_by: {},
        fee_type: :charge,
        payment_status: :pending,
        events_count: 0,
        amount_currency: invoice.currency,
        amount_cents: 0,
        precise_amount_cents: 0.to_d,
        unit_amount_cents: 0,
        precise_unit_amount: 0.to_d,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        units: 0,
        total_aggregated_units: 0,
        properties: boundaries
      )
    end
  end
end
