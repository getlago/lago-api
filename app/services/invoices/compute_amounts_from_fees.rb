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
      invoice.sub_total_vat_excluded_amount_cents = (
        invoice.fees_amount_cents - invoice.coupons_amount_cents
      )

      invoice.vat_amount_cents = invoice.fees.sum do |fee|
        # NOTE: Because coupons are applied before VAT,
        #       we have to distribute the coupons amount at prorata of each fees
        #       compared to the invoice total fees amount
        fee_rate = invoice.fees_amount_cents.zero? ? 0 : fee.amount_cents.fdiv(invoice.fees_amount_cents)
        prorated_coupon_amount = fee_rate * invoice.coupons_amount_cents
        (fee.amount_cents - prorated_coupon_amount) * fee.vat_rate
      end.fdiv(100).round

      invoice.sub_total_vat_included_amount_cents = (
        invoice.sub_total_vat_excluded_amount_cents + invoice.vat_amount_cents
      )
      invoice.total_amount_cents = (
        invoice.sub_total_vat_included_amount_cents - invoice.credit_notes_amount_cents
      )

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice
  end
end
