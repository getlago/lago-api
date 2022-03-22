# frozen_string_literal: true

module Mutations
  module Products
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateProduct'

      argument :id, String, required: true
      argument :name, String, required: true
      argument :billable_metric_ids, [String]

      type Types::Products::Object

      def resolve(**args)
        result = ProductsService.new(context[:current_user]).update(**args)

        result.success? ? result.product : execution_error(code: result.error_code, message: result.message)
      end
    end
  end
end
