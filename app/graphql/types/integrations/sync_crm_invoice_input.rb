# frozen_string_literal: true

module Types
  module Integrations
    class SyncCrmInvoiceInput < Types::BaseInputObject
      graphql_name 'SyncCrmIntegrationInvoiceInput'

      argument :invoice_id, ID, required: true
    end
  end
end
