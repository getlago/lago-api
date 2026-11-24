# frozen_string_literal: true

module Mutations
  module IntegrationItems
    class FetchCustomers < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "organization:integrations:update"

      graphql_name "FetchIntegrationCustomers"
      description "Fetch integration customers"

      argument :integration_id, ID, required: true

      type Types::IntegrationItems::Object.collection_type, null: false

      def resolve(**args)
        integration = current_organization.integrations.find_by(id: args[:integration_id])
        return not_found_error(resource: "integration") unless integration.is_a?(::Integrations::QuickbooksIntegration)

        ::Integrations::Aggregator::SyncService.call(integration:, options: {only_customers: true})

        result = ::Integrations::Aggregator::CustomersService.call(integration:)

        result.success? ? result.customers : result_error(result)
      end
    end
  end
end
