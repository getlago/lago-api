# frozen_string_literal: true

module Mutations
  module Orders
    class Execute < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "orders:execute"

      graphql_name "ExecuteOrder"
      description "Execute an order"

      input_object_class Types::Orders::ExecuteInput

      type Types::Orders::Object

      def resolve(**args)
        order = current_organization.orders.find_by(id: args[:id])
        result = ::Orders::ExecuteService.call(order:)

        result.success? ? result.order : result_error(result)
      end
    end
  end
end
