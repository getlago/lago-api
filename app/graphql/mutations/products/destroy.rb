# frozen_string_literal: true

module Mutations
  module Products
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyProduct'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = ProductsService.new(context[:current_user]).destroy(id)

        result.success? ? result.product : execution_error(code: result.error, message: result.error)
      end
    end
  end
end
