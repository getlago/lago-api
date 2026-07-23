# frozen_string_literal: true

module Mutations
  module IntegrationCustomers
    class SetAsDefault < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "SetIntegrationCustomerAsDefault"
      description "Set an integration connection as the default for its category"

      REQUIRED_PERMISSION = "customers:update"

      argument :code, String, required: true
      argument :customer_id, ID, required: true

      type Types::IntegrationCustomers::Object

      def resolve(**args)
        customer = current_organization.customers.find_by(id: args[:customer_id])
        integration_customer = customer&.integration_customers&.find_by(code: args[:code])

        result = ::IntegrationCustomers::SetAsDefaultService.call(integration_customer:)

        result.success? ? result.integration_customer : result_error(result)
      end
    end
  end
end
