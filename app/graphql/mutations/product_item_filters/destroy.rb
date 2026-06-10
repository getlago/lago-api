# frozen_string_literal: true

module Mutations
  module ProductItemFilters
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_items:delete"

      graphql_name "DestroyProductItemFilter"
      description "Deletes a product item filter"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        product_item_filter = current_organization.product_item_filters.find_by(id:)
        result = ::ProductItemFilters::DestroyService.call(product_item_filter:)

        result.success? ? result.product_item_filter : result_error(result)
      end
    end
  end
end
