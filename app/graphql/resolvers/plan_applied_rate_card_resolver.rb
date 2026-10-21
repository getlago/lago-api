# frozen_string_literal: true

module Resolvers
  class PlanAppliedRateCardResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "plans:view"

    description "Query a single rate card applied to a plan"

    argument :id, ID, required: true, description: "Uniq ID of the applied rate card"

    type Types::PlanAppliedRateCards::Object, null: true

    def resolve(id: nil)
      PlanRateCard.where(organization: current_organization).find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "applied_rate_card")
    end
  end
end
