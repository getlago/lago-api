# frozen_string_literal: true

module Invoices
  class ComputeAmountsFromFees < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      invoice.amount_cents = invoice.fees.sum(:amount_cents)
      invoice.vat_amount_cents = invoice.fees.sum { |f| f.amount_cents * f.vat_rate }.fdiv(100).round
      invoice.credit_amount_cents = 0 if invoice.credits.empty?
      invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents - invoice.credit_amount_cents

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice
  end
end
