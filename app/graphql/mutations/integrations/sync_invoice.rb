# frozen_string_literal: true

module Mutations
  module Integrations
    class SyncInvoice < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:update'

      graphql_name 'SyncIntegrationInvoice'
      description 'Sync integration invoice'

      argument :invoice_id, ID, required: true

      type Types::IntegrationItems::Object.collection_type, null: false

      def resolve(**args)
        ::Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:)

        result
      end
    end
  end
end
