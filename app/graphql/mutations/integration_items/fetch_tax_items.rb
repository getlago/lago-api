# frozen_string_literal: true

module Mutations
  module IntegrationItems
    class FetchTaxItems < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:update'

      graphql_name 'FetchIntegrationTaxItems'
      description 'Fetch integration tax items'

      argument :integration_id, ID, required: true

      type Types::IntegrationItems::Object.collection_type, null: false

      def resolve(**args)
        integration = current_organization.integrations.find_by(id: args[:integration_id])

        ::Integrations::Aggregator::SyncService.call(integration:)

        result = ::Integrations::Aggregator::TaxItemsService.call(integration:)

        result.success? ? result.tax_items : result_error(result)
      end
    end
  end
end
