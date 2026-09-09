# frozen_string_literal: true

module Resolvers
  class ProductCategoriesResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_categories:view"

    description "Query product_categories of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::ProductCategories::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil)
      result = ::ProductCategoriesQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:}
      )

      result.product_categories
    end
  end
end
