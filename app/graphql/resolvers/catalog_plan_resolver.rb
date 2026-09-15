# frozen_string_literal: true

module Resolvers
  class CatalogPlanResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "plans:view"

    description "Query a single catalog plan of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the catalog plan"

    type Types::CatalogPlans::Object, null: true

    def resolve(id: nil)
      current_organization.catalog_plans.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "plan")
    end
  end
end
