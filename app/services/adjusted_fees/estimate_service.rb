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
      return result.forbidden_failure! if !License.premium?

      fee = Fee.find_by(id: params[:fee_id])
      return result.not_found_failure!(resource: "fee") if fee.blank?

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
        charge_filter: fee.charge_filter,
        organization:
      )

      adjustement_result = Fees::InitFromAdjustedChargeFeeService.call(
        adjusted_fee: adjusted_fee,
        boundaries: adjusted_fee.properties,
        properties: charge.properties
      )

      adjustement_result.fee.id = SecureRandom.uuid
      result.fee = adjustement_result.fee
      result
    end

    private

    attr_reader :organization, :invoice, :params
    def disabled_charge_model?(charge)
      unit_adjustment = params[:units].present? && params[:unit_precise_amount].blank?

      charge && unit_adjustment && (charge.percentage? || (charge.prorated? && charge.graduated?))
    end
  end
end