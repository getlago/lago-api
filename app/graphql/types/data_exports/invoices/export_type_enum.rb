# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataExports
    module Invoices
      class ExportTypeEnum < Types::BaseEnum
        graphql_name "InvoiceExportTypeEnum"

        value "invoices"
        value "invoice_fees"
      end
    end
  end
end
