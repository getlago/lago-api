# frozen_string_literal: true

module Mutations
  module IntegrationCustomers
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:update"

      graphql_name "DestroyIntegrationCustomer"
      description "Deletes an integration customer connection"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        integration_customer = ::IntegrationCustomers::BaseCustomer
          .where(organization_id: current_organization.id)
          .find_by(id:)

        result = ::IntegrationCustomers::DestroyService.call(integration_customer:)

        result.success? ? result.integration_customer : result_error(result)
      end
    end
  end
end
