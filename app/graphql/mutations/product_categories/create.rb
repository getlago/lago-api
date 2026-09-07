# frozen_string_literal: true

module Mutations
  module ProductCategories
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_categories:create"

      graphql_name "CreateProductCategory"
      description "Creates a new product_category"

      input_object_class Types::ProductCategories::CreateInput
      type Types::ProductCategories::Object

      def resolve(**args)
        result = ::ProductCategories::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.product_category : result_error(result)
      end
    end
  end
end
