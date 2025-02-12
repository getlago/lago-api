# frozen_string_literal: true

module Invoices
  class AggregateAmountsAndTaxesFromFees < BaseService
    Result = BaseResult

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    # NOTE: progressing billing, coupons and credit notes are not supported here
    def call
      return result if invoice.fees.empty?

      # TODO: Return error if some fees are :succeeded

      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.taxes_amount_cents = invoice.fees.sum(&:taxes_amount_cents)
      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents
      invoice.sub_total_including_taxes_amount_cents = invoice.sub_total_excluding_taxes_amount_cents + invoice.taxes_amount_cents

      invoice.applied_taxes = invoice.fees.flat_map(&:applied_taxes).group_by(&:tax_id).map do |tax_id, taxes|
        t = taxes.first
        Invoice::AppliedTax.new(
          tax_id: tax_id,
          tax_name: t.tax_name,
          tax_code: t.tax_code,
          tax_description: t.tax_description,
          tax_rate: t.tax_rate,
          amount_currency: t.amount_currency,

          amount_cents: taxes.sum(&:amount_cents),
          fees_amount_cents: taxes.sum(&:amount_cents),
          taxable_base_amount_cents: taxes.sum(&:precise_amount_cents), # ???
        )
      end

      result
    end

    private

    attr_reader :invoice
  end
end
