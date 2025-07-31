# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      COMMERCIAL_INVOICE = 380
      PREPAID_INVOICE = 386

      class Header < Builder
        def call
          xml.comment "Exchange Document Header"
          xml["rsm"].ExchangedDocument do
            xml["ram"].ID invoice.number
            xml["ram"].TypeCode invoice_type_code
            xml["ram"].IssueDateTime do
              xml["udt"].DateTimeString formatted_date(invoice.issuing_date), format: CCYYMMDD
            end
            xml["ram"].IncludedNote do
              xml["ram"].Content "Invoice ID: #{invoice.id}"
            end
          end
        end

        private

        def invoice_type_code
          if invoice.credit?
            PREPAID_INVOICE
          else
            COMMERCIAL_INVOICE
          end
        end
      end
    end
  end
end
