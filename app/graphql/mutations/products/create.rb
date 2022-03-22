# frozen_string_literal: true

module Mutations
  module Products
    class Create < BaseMutation
      include AuthenticableApiUser

      description 'Creates a new product'
      graphql_name 'CreateProduct'

      argument :organization_id, String, required: true
      argument :name, String, required: true
      argument :billable_metric_ids, [String]

      type Types::Products::Object

      def resolve(**args)
        result = ProductsService.new(context[:current_user]).create(**args)

        result.success? ? result.product : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
