# frozen_string_literal: true

module Mutations
  module ProductFilters
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_filters:create"

      graphql_name "CreateProductFilter"
      description "Creates a new product filter"

      input_object_class Types::ProductFilters::CreateInput
      type Types::ProductFilters::Object

      def resolve(**args)
        product = current_organization.products.find_by(id: args[:product_id])
        result = ::ProductFilters::CreateService.call(
          product:,
          params: args.except(:product_id).merge(values: args[:values].map(&:to_h))
        )

        result.success? ? result.product_filter : result_error(result)
      end
    end
  end
end
