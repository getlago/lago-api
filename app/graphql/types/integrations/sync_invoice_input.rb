# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class SyncInvoiceInput < Types::BaseInputObject
      graphql_name "SyncIntegrationInvoiceInput"

      argument :invoice_id, ID, required: true
    end
  end
end
