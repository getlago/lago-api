# frozen_string_literal: true

module Resolvers
  class CatalogPlansResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "plans:view"

    description "Query catalog plans of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    argument :product_category_ids, [ID], required: false
    argument :product_filter_ids, [ID], required: false
    argument :product_ids, [ID], required: false
    argument :rate_card_ids, [ID], required: false

    type Types::CatalogPlans::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, product_ids: nil, product_filter_ids: nil, product_category_ids: nil, rate_card_ids: nil)
      result = CatalogPlansQuery.call(
        organization: current_organization,
        search_term:,
        filters: {product_ids:, product_filter_ids:, product_category_ids:, rate_card_ids:},
        pagination: {
          page:,
          limit:
        }
      )

      result.catalog_plans
    end
  end
end
