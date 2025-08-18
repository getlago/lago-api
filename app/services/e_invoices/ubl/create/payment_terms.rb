# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class PaymentTerms < Builder
        def call
          xml.comment "Payment Terms"
          xml["cac"].PaymentTerms do
            xml["cbc"].Note note
          end
        end

        private

        def note
          [payment_terms_description, payments].flatten.to_sentence
        end

        def payments
          {
            PREPAID => invoice.prepaid_credit_amount,
            CREDIT_NOTE => invoice.credit_notes_amount
          }.map do |type, amount|
            next unless amount.positive?

            payment_information(type, amount)
          end.compact
        end
      end
    end
  end
end
