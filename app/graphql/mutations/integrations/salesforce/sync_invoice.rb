# frozen_string_literal: true

module Mutations
  module Integrations
    module Salesforce
      class SyncInvoice < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = 'organization:integrations:update'

        graphql_name 'SyncSalesforceInvoice'
        description 'Sync Salesforce invoice'

        input_object_class Types::Integrations::Salesforce::SyncInvoiceInput

        field :invoice_id, ID, null: true

        def resolve(**args)
          invoice = current_organization.invoices.find_by(id: args[:invoice_id])
          SendWebhookJob.perform_later('invoice.resynced', invoice)
        end
      end
    end
  end
end
