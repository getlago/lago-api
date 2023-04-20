# frozen_string_literal: true

module Invoices
  class ComputeAmountsFromFees < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
      invoice.sub_total_vat_excluded_amount_cents = invoice.fees_amount_cents
      invoice.vat_amount_cents = invoice.fees.sum { |f| f.amount_cents * f.vat_rate }.fdiv(100).round
      invoice.sub_total_vat_included_amount_cents = (
        invoice.sub_total_vat_excluded_amount_cents + invoice.vat_amount_cents
      )
      invoice.total_amount_cents = invoice.sub_total_vat_included_amount_cents -
                                   invoice.credit_notes_amount_cents -
                                   invoice.coupons_amount_cents -
                                   invoice.prepaid_credit_amount_cents

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice
  end
end
