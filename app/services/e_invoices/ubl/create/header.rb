# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class Header < Builder
        def call
          xml.comment "Invoice Header Information"
          xml["cbc"].ID invoice.number
          xml["cbc"].IssueDate formatted_date(invoice.issuing_date)
          xml["cbc"].InvoiceTypeCode invoice_type_code
          xml["cbc"].Note note if note.present?
          xml["cbc"].DocumentCurrencyCode invoice.currency
        end

        private

        def note
          @_note ||= {
            PREPAID => invoice.prepaid_credit_amount,
            CREDIT_NOTE => invoice.credit_notes_amount
          }.map do |type, amount|
            next unless amount.positive?

            payment_information(type, amount)
          end.compact.to_sentence
        end
      end
    end
  end
end
