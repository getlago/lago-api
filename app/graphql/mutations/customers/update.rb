# frozen_string_literal: true

module Mutations
  module Customers
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateCustomer'
      description 'Updates an existing Customer'

      argument :id, ID, required: true
      argument :name, String, required: true
      argument :customer_id, String, required: true

      type Types::Customers::Object

      def resolve(**args)
        result = CustomersService.new(context[:current_user]).update(**args)

        result.success? ? result.customer : execution_error(code: result.error_code, message: result.message)
      end
    end
  end
end
