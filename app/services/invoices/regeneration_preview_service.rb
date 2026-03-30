# frozen_string_literal: true

module Invoices
  class RegenerationPreviewService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      draft_invoice = invoice.dup
      invoice.fees.each do |fee|
        result = ::AdjustedFees::EstimateService.call(
          invoice: invoice,
          params: {
            invoice_subscription_id: fee.subscription_id,
            fee_type: fee.fee_type,
            units: fee.units,
            unit_precise_amount: fee.amount.currency.subunit_to_unit,
            charge_id: fee.charge_id,
            charge_filter_id: fee.charge_filter_id,
            fixed_charge_id: fee.fixed_charge_id,
            invoice_display_name: fee.invoice_display_name
          }
        )
        result.raise_if_error!

        result.fee.id = fee.id
        result.fee.adjusted_fee = nil
        draft_invoice.fees << result.fee
      end

      result = Invoices::ComputeAmountsFromFees.call(invoice: draft_invoice, provider_taxes: nil)
      result.raise_if_error!

      result.invoice.id = invoice.id
      result.invoice.applied_taxes.each do |applied_tax|
        applied_tax.invoice_id = invoice.id
        applied_tax.id = SecureRandom.uuid
      end

      result
    end

    private

    attr_reader :invoice
  end
end
