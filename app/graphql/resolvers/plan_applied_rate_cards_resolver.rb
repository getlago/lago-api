# frozen_string_literal: true

module Resolvers
  class PlanAppliedRateCardsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "plans:view"

    description "Query rate cards applied to a plan"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :plan_id, ID, required: false

    type Types::PlanAppliedRateCards::Object.collection_type, null: false

    def resolve(plan_id: nil, page: nil, limit: nil)
      result = ::PlanRateCardsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {plan_id:}
      )

      result.plan_rate_cards
    end
  end
end
