# frozen_string_literal: true

module Resolvers
  class ProductFiltersResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_filters:view"

    description "Query product filters of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_category_ids, [ID], required: false
    argument :product_id, ID, required: false
    argument :search_term, String, required: false
    argument :without_product_category, Boolean, required: false

    type Types::ProductFilters::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_id: nil, product_category_ids: nil, without_product_category: nil)
      result = ::ProductFiltersQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: {product_id:, product_category_ids:, without_product_category:}
      )

      result.product_filters
    end
  end
end
