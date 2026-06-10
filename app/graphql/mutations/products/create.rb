# frozen_string_literal: true

module Mutations
  module Products
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "products:create"

      graphql_name "CreateProduct"
      description "Creates a new product"

      input_object_class Types::Products::CreateInput
      type Types::Products::Object

      def resolve(**args)
        result = ::Products::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.product : result_error(result)
      end
    end
  end
end
