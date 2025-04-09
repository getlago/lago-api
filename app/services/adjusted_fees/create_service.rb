# frozen_string_literal: true

module AdjustedFees
  class CreateService < BaseService
    def initialize(invoice:, params:)
      @invoice = invoice
      @organization = invoice.organization
      @params = params

      super
    end

    def call
      return result.forbidden_failure! if !License.premium? || !invoice.draft?

      fee = find_or_create_fee
      return result unless result.success?
      return result.validation_failure!(errors: {adjusted_fee: ["already_exists"]}) if fee.adjusted_fee

      charge = fee.charge
      return result.validation_failure!(errors: {charge: ["invalid_charge_model"]}) if disabled_charge_model?(charge)

      unit_precise_amount_cents = params[:unit_precise_amount].to_f * fee.amount.currency.subunit_to_unit
      adjusted_fee = AdjustedFee.new(
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
        charge_filter: fee.charge_filter
      )
      adjusted_fee.save!

      subscription_id = fee.subscription_id
      charge_id = fee.charge_id
      charge_filter_id = fee.charge_filter_id

      refresh_result = Invoices::RefreshDraftService.call(invoice: invoice)
      refresh_result.raise_if_error!

      result.adjusted_fee = adjusted_fee.reload
      result.fee = invoice.fees.find_by(subscription_id:, charge_id:, charge_filter_id:)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :invoice, :params

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
      subscription = invoice.subscriptions.includes(plan: {charges: :filters}).find_by(id: params[:subscription_id])
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

      Fee.create!(
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

    def disabled_charge_model?(charge)
      unit_adjustment = params[:units].present? && params[:unit_precise_amount].blank?

      charge && unit_adjustment && (charge.percentage? || (charge.prorated? && charge.graduated?))
    end
  end
end
