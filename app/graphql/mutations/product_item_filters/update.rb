# frozen_string_literal: true

module Mutations
  module ProductItemFilters
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_items:update"

      graphql_name "UpdateProductItemFilter"
      description "Updates an existing product item filter"

      input_object_class Types::ProductItemFilters::UpdateInput
      type Types::ProductItemFilters::Object

      def resolve(**args)
        product_item_filter = current_organization.product_item_filters.find_by(id: args[:id])

        params = args.except(:id)
        params[:values] = params[:values].map(&:to_h) if params.key?(:values)

        result = ::ProductItemFilters::UpdateService.call(product_item_filter:, params:)

        result.success? ? result.product_item_filter : result_error(result)
      end
    end
  end
end
