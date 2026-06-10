# frozen_string_literal: true

module Mutations
  module Products
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "products:delete"

      graphql_name "DestroyProduct"
      description "Deletes a product"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        product = current_organization.products.find_by(id:)
        result = ::Products::DestroyService.call(product:)

        result.success? ? result.product : result_error(result)
      end
    end
  end
end
