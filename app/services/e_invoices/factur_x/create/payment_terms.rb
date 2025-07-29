# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class PaymentTerms < Builder
        def call
          xml.comment "Payment Terms"
          xml["ram"].SpecifiedTradePaymentTerms do
            xml["ram"].Description "Net payment term: 0 days"
            xml["ram"].DueDateDateTime do
              xml["udt"].DateTimeString formatted_date("20250626".to_date), format: CCYYMMDD
            end
          end
        end
      end
    end
  end
end
