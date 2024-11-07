# frozen_string_literal: true

module Mutations
  module Integrations
    class SyncInvoice < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:update'

      graphql_name 'SyncSalesforceInvoice'
      description 'Sync Salesforce invoice'

      input_object_class Types::Integrations::SyncInvoiceInput

      field :invoice_id, ID, null: true

      def resolve(**args)
        SendWebhookJob.perform_later('invoice.resynced', invoice)
      end
    end
  end
end
