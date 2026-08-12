# frozen_string_literal: true

module Mutations
  module IntegrationCustomers
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:update"

      graphql_name "CreateIntegrationCustomer"
      description "Creates an integration customer connection"

      input_object_class Types::IntegrationCustomers::CreateInput

      type Types::IntegrationCustomers::Object

      def resolve(customer_id:, **args)
        customer = current_organization.customers.find_by(id: customer_id)

        result = ::IntegrationCustomers::CreateConnectionService.call(customer:, params: args)

        result.success? ? result.integration_customer : result_error(result)
      end
    end
  end
end
