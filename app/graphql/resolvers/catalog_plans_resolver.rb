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

    type Types::CatalogPlans::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil)
      result = CatalogPlansQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {
          page:,
          limit:
        }
      )

      result.catalog_plans
    end
  end
end
