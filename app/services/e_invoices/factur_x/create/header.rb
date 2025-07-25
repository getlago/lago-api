# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      COMMERCIAL_INVOICE = 380

      class Header < Builder
        def call
          xml.comment "Exchange Document Header"
          xml["rsm"].ExchangedDocument do
            xml["ram"].ID invoice.number
            xml["ram"].TypeCode COMMERCIAL_INVOICE
            xml["ram"].IssueDateTime do
              xml["udt"].DateTimeString formatted_date(invoice.issuing_date), format: YYMMDD
            end
            xml["ram"].IncludedNote do
              xml["ram"].Content "Invoice ID: #{invoice.id}"
            end
          end
        end
      end
    end
  end
end
