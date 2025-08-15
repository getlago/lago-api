# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class PaymentTerms < Builder
        def call
          xml.comment "Payment Terms"
          xml["cac"].PaymentTerms do
            xml["cbc"].Note payment_terms_description
          end
        end
      end
    end
  end
end
