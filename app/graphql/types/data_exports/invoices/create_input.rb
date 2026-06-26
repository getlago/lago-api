# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataExports
    module Invoices
      class CreateInput < Types::BaseInputObject
        graphql_name "CreateDataExportsInvoicesInput"

        argument :filters, Types::DataExports::Invoices::FiltersInput
        argument :format, Types::DataExports::FormatTypeEnum
        argument :resource_type, Types::DataExports::Invoices::ExportTypeEnum
      end
    end
  end
end
