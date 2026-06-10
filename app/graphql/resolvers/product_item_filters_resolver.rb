# frozen_string_literal: true

module Resolvers
  class ProductItemFiltersResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_items:view"

    description "Query product item filters of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_item_id, ID, required: false
    argument :search_term, String, required: false

    type Types::ProductItemFilters::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_item_id: nil)
      result = ::ProductItemFiltersQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: {product_item_id:}
      )

      result.product_item_filters
    end
  end
end
