# frozen_string_literal: true

module Resolvers
  class ProductsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "products:view"

    description "Query products of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :product_category_ids, [ID], required: false
    argument :product_type, Types::Products::ProductTypeEnum, required: false
    argument :search_term, String, required: false
    argument :without_product_category, Boolean, required: false

    type Types::Products::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_category_ids: nil, without_product_category: nil, product_type: nil)
      result = ::ProductsQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:},
        filters: {product_category_ids:, without_product_category:, product_type:}
      )

      result.products
    end
  end
end
