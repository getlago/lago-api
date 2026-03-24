# frozen_string_literal: true

module Invoices
  class DraftService < BaseService
    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      draft_invoice = invoice.dup
      invoice.fees.each do |fee|
        result = ::AdjustedFees::EstimateService.call(
          invoice: invoice,
          params: {invoice_subscription_id: fee.subscription_id, fee_type: fee.fee_type, units: fee.units, unit_precise_amount: fee.amount.currency.subunit_to_unit}
        )
        result.fee.id = fee.id
        result.fee.adjusted_fee = nil
        draft_invoice.fees << result.fee
      end

      # FIXME: Investigate the source of provider_taxes
      result = Invoices::ComputeAmountsFromFees.call(invoice: draft_invoice, provider_taxes: nil)
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
