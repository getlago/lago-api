# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class PaymentTerms < Builder
        def call
          xml.comment "Payment Terms"
          xml["ram"].SpecifiedTradePaymentTerms do
            xml["ram"].Description payment_terms_description
            xml["ram"].DueDateDateTime do
              xml["udt"].DateTimeString formatted_date(invoice.payment_due_date), format: CCYYMMDD
            end
          end
        end
      end
    end
  end
end
