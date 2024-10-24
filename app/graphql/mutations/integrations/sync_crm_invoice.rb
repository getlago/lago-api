# frozen_string_literal: true

module Mutations
  module Integrations
    class SyncCrmInvoice < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:update'

      graphql_name 'SyncCrmIntegrationInvoice'
      description 'Sync crm integration invoice'

      input_object_class Types::Integrations::SyncCrmInvoiceInput

      field :invoice_id, ID, null: true

      def resolve(**args)
        invoice = current_organization.invoices.find_by(id: args[:invoice_id])

        result = ::Integrations::Aggregator::Invoices::Crm::CreateService.call_async(invoice:)
        result.success? ? result.invoice_id : result_error(result)
        result
      end
    end
  end
end
