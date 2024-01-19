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
      return result.validation_failure!(errors: { adjusted_fee: ['already_exists'] }) if fee.adjusted_fee

      charge = fee.charge
      if charge && params[:unit_amount_cents].blank? && (charge.percentage? || (charge.prorated? && charge.graduated?))
        return result.validation_failure!(errors: { charge: ['invalid_charge_model'] })
      end

      adjusted_fee = AdjustedFee.new(
        fee:,
        invoice: fee.invoice,
        subscription: fee.subscription,
        charge:,
        group: fee.group,
        adjusted_units: params[:unit_amount_cents].blank?,
        adjusted_amount: params[:unit_amount_cents].present?,
        invoice_display_name: params[:invoice_display_name],
        fee_type: fee.fee_type,
        properties: fee.properties,
        units: params[:units].presence || 0,
        unit_amount_cents: params[:unit_amount_cents].presence || 0,
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
  end
end
