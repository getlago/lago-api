# frozen_string_literal: true

module Mutations
  module IntegrationCustomers
    class SetAsDefault < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "SetIntegrationCustomerAsDefault"
      description "Set an integration connection as the default for its category"

      REQUIRED_PERMISSION = "customers:update"

      argument :id, ID, required: true

      type Types::IntegrationCustomers::Object

      def resolve(id:)
        integration_customer = ::IntegrationCustomers::BaseCustomer
          .where(organization_id: current_organization.id)
          .find_by(id:)

        result = ::IntegrationCustomers::SetAsDefaultService.call(integration_customer:)

        result.success? ? result.integration_customer : result_error(result)
      end
    end
  end
end
