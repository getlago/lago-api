# frozen_string_literal: true

module Mutations
  module ProductFilters
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "product_filters:update"

      graphql_name "UpdateProductFilter"
      description "Updates an existing product filter"

      input_object_class Types::ProductFilters::UpdateInput
      type Types::ProductFilters::Object

      def resolve(**args)
        product_filter = current_organization.product_filters.find_by(id: args[:id])

        params = args.except(:id)
        params[:values] = params[:values]&.map(&:to_h) if params.key?(:values)

        result = ::ProductFilters::UpdateService.call(product_filter:, params:)

        result.success? ? result.product_filter : result_error(result)
      end
    end
  end
end
