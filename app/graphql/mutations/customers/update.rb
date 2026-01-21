# frozen_string_literal: true

module Mutations
  module Customers
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = %w[customers:update]

      graphql_name "UpdateCustomer"
      description "Updates an existing Customer"

      input_object_class Types::Customers::UpdateCustomerInput

      type Types::Customers::Object

      def resolve(**args)
        customer = context[:current_user].customers.find_by(id: args[:id])
        result = ::Customers::UpdateService.call(customer:, args:)

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
