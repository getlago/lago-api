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
        result = ::Customers::DestroyService.new(context[:current_user]).destroy(id: id)

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
