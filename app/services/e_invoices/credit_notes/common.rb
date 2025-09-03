# frozen_string_literal: true

module EInvoices
  module CreditNotes
    module Common
      def resource
        credit_note
      end

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
    end
  end
end
