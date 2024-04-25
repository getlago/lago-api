# frozen_string_literal: true

module Mutations
  module Customers
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = 'customers:update'

      graphql_name 'UpdateCustomer'
      description 'Updates an existing Customer'

      input_object_class Types::Customers::UpdateCustomerInput

      type Types::Customers::Object

      def resolve(**args)
        result = ::Customers::UpdateService.new(context[:current_user]).update(**args)

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
