# frozen_string_literal: true

module Mutations
  module ProductCategories
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_categories:update"

      graphql_name "UpdateProductCategory"
      description "Updates an existing product_category"

      input_object_class Types::ProductCategories::UpdateInput
      type Types::ProductCategories::Object

      def resolve(**args)
        product_category = current_organization.product_categories.find_by(id: args[:id])
        result = ::ProductCategories::UpdateService.call(product_category:, params: args.except(:id))

        result.success? ? result.product_category : result_error(result)
      end
    end
  end
end
