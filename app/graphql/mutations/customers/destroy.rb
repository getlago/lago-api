# frozen_string_literal: true

module Mutations
  module Customers
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyCustomer'
      description 'Delete a Customer'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = CustomersService.new(context[:current_user]).destroy(id: id)

        result.success? ? result.customer : execution_error(code: result.error, message: result.error)
      end
    end
  end
end
