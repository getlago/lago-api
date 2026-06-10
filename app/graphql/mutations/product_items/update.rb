# frozen_string_literal: true

module Mutations
  module ProductItems
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_items:update"

      graphql_name "UpdateProductItem"
      description "Updates an existing product item"

      input_object_class Types::ProductItems::UpdateInput
      type Types::ProductItems::Object

      def resolve(**args)
        product_item = current_organization.product_items.find_by(id: args[:id])
        result = ::ProductItems::UpdateService.call(product_item:, params: args.except(:id))

        result.success? ? result.product_item : result_error(result)
      end
    end
  end
end
