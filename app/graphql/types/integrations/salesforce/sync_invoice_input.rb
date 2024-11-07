# frozen_string_literal: true

module Types
  module Integrations
    module Salesforce
      class SyncInvoiceInput < Types::BaseInputObject
        graphql_name 'SyncSalesforceInvoiceInput'

        argument :invoice_id, ID, required: true
      end
    end
  end
end
