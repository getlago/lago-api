# frozen_string_literal: true

module AdjustedFees
  class CreateService < BaseService
    def initialize(organization:, fee:, params:)
      @organization = organization
      @fee = fee
      @params = params

      super
    end

    def call
      return result.forbidden_failure! if !License.premium? || !fee.invoice.draft?
      return result.validation_failure!(errors: {adjusted_fee: ['already_exists']}) if fee.adjusted_fee

      charge = fee.charge
      return result.validation_failure!(errors: {charge: ['invalid_charge_model']}) if disabled_charge_model?(charge)

      adjusted_fee = AdjustedFee.new(
        fee:,
        invoice: fee.invoice,
        subscription: fee.subscription,
        charge:,
        adjusted_units: params[:units].present? && params[:unit_amount_cents].blank?,
        adjusted_amount: params[:units].present? && params[:unit_amount_cents].present?,
        invoice_display_name: params[:invoice_display_name],
        fee_type: fee.fee_type,
        properties: fee.properties,
        units: params[:units].presence || 0,
        unit_amount_cents: params[:unit_amount_cents].presence || 0,
        grouped_by: fee.grouped_by,
        charge_filter: fee.charge_filter,
      )

      adjusted_fee.save!

      refresh_result = Invoices::RefreshDraftService.call(invoice: fee.invoice)
      refresh_result.raise_if_error!

      result.adjusted_fee = adjusted_fee
      result.fee = fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :fee, :params

    def disabled_charge_model?(charge)
      unit_adjustment = params[:units].present? && params[:unit_amount_cents].blank?

      charge && unit_adjustment && (charge.percentage? || (charge.prorated? && charge.graduated?))
    end
  end
end
