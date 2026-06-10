# frozen_string_literal: true

module Mutations
  module ProductItems
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_items:delete"

      graphql_name "DestroyProductItem"
      description "Deletes a product item"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        product_item = current_organization.product_items.find_by(id:)
        result = ::ProductItems::DestroyService.call(product_item:)

        result.success? ? result.product_item : result_error(result)
      end
    end
  end
end
