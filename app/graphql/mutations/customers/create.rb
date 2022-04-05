# frozen_string_literal: true

module Mutations
  module Customers
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCustomer'
      description 'Creates a new customer'

      argument :name, String, required: true
      argument :customer_id, String, required: true

      type Types::Customers::Object

      def resolve(**args)
        validate_organization!

        result = CustomersService
          .new(context[:current_user])
          .create(organization: current_organization, params: args)

        result.success? ? result.customer : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
