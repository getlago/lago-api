# frozen_string_literal: true

module Mutations
  module Products
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization
      include SurfaceErrorFields

      REQUIRED_PERMISSION = "products:create"

      graphql_name "CreateProduct"
      description "Creates a new product"

      input_object_class Types::Products::CreateInput
      type Types::Products::Object

      def resolve(**args)
        result = ::Products::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.product : render_item_error(result)
      end
    end
  end
end
