# frozen_string_literal: true

module EInvoices
  module CreditNotes
    module Common
      def notes
        [
          "Credit Note ID: #{credit_note.id}",
          "Original Invoice: #{credit_note.invoice.number}",
          "Reason: #{credit_note.reason}"
        ]
      end

      def credits_and_payments(&block)
        yield EInvoices::BaseService::STANDARD_PAYMENT, credit_note.credit_amount
      end

      def taxes(&block)
        zero_rated_taxes = resource.items.joins(:fee).where(fee: {taxes_rate: 0})
        if zero_rated_taxes.exists?
          amount_categories = zero_rated_taxes.each_with_object(Hash.new(0)) do |item, hash|
            category = tax_category_code(type: item.fee.fee_type, tax_rate: item.fee.taxes_rate)
            hash[category] += item.precise_amount_cents
          end

          amount_categories.each do |category, basis_amount|
            yield category, 0, Money.new(basis_amount), 0
          end
        end

        resource.applied_taxes.each do |applied_tax|
          tax_rate = applied_tax.tax_rate
          tax_amount = applied_tax.amount_cents
          basis_amount = applied_tax.base_amount_cents
          tax_category = tax_category_code(tax_rate: tax_rate)

          yield tax_category, tax_rate, Money.new(basis_amount), Money.new(tax_amount)
        end
      end
    end
  end
end
