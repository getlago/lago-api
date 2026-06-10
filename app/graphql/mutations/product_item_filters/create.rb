# frozen_string_literal: true

module Mutations
  module ProductItemFilters
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_items:create"

      graphql_name "CreateProductItemFilter"
      description "Creates a new product item filter"

      input_object_class Types::ProductItemFilters::CreateInput
      type Types::ProductItemFilters::Object

      def resolve(**args)
        product_item = current_organization.product_items.find_by(id: args[:product_item_id])
        result = ::ProductItemFilters::CreateService.call(
          product_item:,
          params: args.except(:product_item_id).merge(values: args[:values].map(&:to_h))
        )

        result.success? ? result.product_item_filter : result_error(result)
      end
    end
  end
end
