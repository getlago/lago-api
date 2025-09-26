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
        resource.fees.group_by(&:taxes_rate).each do |tax_rate, fees|
          basis_amount = fees.flat_map(&:credit_note_items).sum(&:precise_amount_cents) - (discounts[tax_rate] || 0)
          tax_amount = basis_amount * tax_rate.fdiv(100)
          tax_category = tax_category_code(type: fees.first.fee_type, tax_rate: tax_rate)

          yield tax_category, tax_rate, Money.new(basis_amount), Money.new(tax_amount)
        end
      end

      def discounts
        @_discounts ||= allowances_per_tax_rate(resource.invoice)
      end
    end
  end
end
