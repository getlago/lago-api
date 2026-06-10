# frozen_string_literal: true

module Mutations
  module ProductItems
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_items:create"

      graphql_name "CreateProductItem"
      description "Creates a new product item"

      input_object_class Types::ProductItems::CreateInput
      type Types::ProductItems::Object

      def resolve(**args)
        result = ::ProductItems::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.product_item : result_error(result)
      end
    end
  end
end
