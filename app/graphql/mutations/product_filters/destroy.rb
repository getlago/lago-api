# frozen_string_literal: true

module Mutations
  module ProductFilters
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_filters:delete"

      graphql_name "DestroyProductFilter"
      description "Deletes a product filter"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        product_filter = current_organization.product_filters.find_by(id:)
        result = ::ProductFilters::DestroyService.call(product_filter:)

        result.success? ? result.product_filter : result_error(result)
      end
    end
  end
end
