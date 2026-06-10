# frozen_string_literal: true

module Resolvers
  class ProductItemsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_items:view"

    description "Query product items of an organization"

    argument :item_types, [Types::ProductItems::ItemTypeEnum], required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_id, ID, required: false
    argument :search_term, String, required: false

    type Types::ProductItems::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_id: nil, item_types: nil)
      result = ::ProductItemsQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: {product_id:, item_types:}
      )

      result.product_items
    end
  end
end
