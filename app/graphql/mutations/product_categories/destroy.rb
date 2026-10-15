# frozen_string_literal: true

module Mutations
  module ProductCategories
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_categories:delete"

      graphql_name "DestroyProductCategory"
      description "Deletes a product_category"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        product_category = current_organization.product_categories.find_by(id:)
        result = ::ProductCategories::DestroyService.call(product_category:)

        result.success? ? result.product_category : result_error(result)
      end
    end
  end
end
