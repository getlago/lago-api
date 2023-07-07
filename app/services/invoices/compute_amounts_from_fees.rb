# frozen_string_literal: true

module Invoices
  class ComputeAmountsFromFees < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
      invoice.coupons_amount_cents = invoice.credits.coupon_kind.sum(:amount_cents)
      invoice.sub_total_excluding_taxes_amount_cents = (
        invoice.fees_amount_cents - invoice.coupons_amount_cents
      )

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!

      invoice.sub_total_including_taxes_amount_cents = (
        invoice.sub_total_excluding_taxes_amount_cents + invoice.taxes_amount_cents
      )
      invoice.total_amount_cents = (
        invoice.sub_total_including_taxes_amount_cents - invoice.credit_notes_amount_cents
      )

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice
  end
end
