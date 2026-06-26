# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class SyncHubspotInvoiceInput < Types::BaseInputObject
      graphql_name "SyncHubspotIntegrationInvoiceInput"

      argument :invoice_id, ID, required: true
    end
  end
end
