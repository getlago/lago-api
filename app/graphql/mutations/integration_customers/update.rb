# frozen_string_literal: true

module Mutations
  module IntegrationCustomers
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:update"

      graphql_name "UpdateIntegrationCustomer"
      description "Updates an integration customer connection"

      input_object_class Types::IntegrationCustomers::UpdateInput

      type Types::IntegrationCustomers::Object

      def resolve(id:, **args)
        integration_customer = ::IntegrationCustomers::BaseCustomer
          .where(organization_id: current_organization.id)
          .find_by(id:)

        result = ::IntegrationCustomers::UpdateConnectionService.call(
          integration_customer:,
          params: args
        )

        result.success? ? result.integration_customer : result_error(result)
      end
    end
  end
end
