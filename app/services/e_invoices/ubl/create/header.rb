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
          xml["cbc"].DocumentCurrencyCode invoice.currency
        end
      end
    end
  end
end
