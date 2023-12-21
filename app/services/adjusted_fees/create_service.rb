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

      adjusted_fee = AdjustedFee.new(
        fee:,
        invoice: fee.invoice,
        subscription: fee.subscription,
        charge: fee.charge,
        adjusted_units: params[:unit_amount_cents]&.blank?,
        adjusted_amount: params[:unit_amount_cents]&.present?,
        invoice_display_name: params[:invoice_display_name],
        fee_type: fee.fee_type,
        properties: fee.properties,
        units: params[:units],
        unit_amount_cents: params[:unit_amount_cents],
      )

      adjusted_fee.save!

      Invoices::RefreshBatchJob.perform_later([fee.invoice_id])

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
