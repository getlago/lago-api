# frozen_string_literal: true

module Mutations
  module Products
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization
      include SurfaceErrorFields

      REQUIRED_PERMISSION = "products:update"

      graphql_name "UpdateProduct"
      description "Updates an existing product"

      input_object_class Types::Products::UpdateInput
      type Types::Products::Object

      def resolve(**args)
        product = current_organization.products.find_by(id: args[:id])
        result = ::Products::UpdateService.call(product:, params: args.except(:id))

        result.success? ? result.product : render_item_error(result)
      end
    end
  end
end
