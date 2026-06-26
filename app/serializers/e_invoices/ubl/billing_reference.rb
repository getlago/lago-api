# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module EInvoices
  module Ubl
    class BillingReference < BaseSerializer
      def serialize
        xml.comment "Reference to Original Invoice"
        xml["cac"].BillingReference do
          xml["cac"].InvoiceDocumentReference do
            xml["cbc"].ID resource.number
            xml["cbc"].IssueDate formatted_date(resource.issuing_date)
          end
        end
      end
    end
  end
end
