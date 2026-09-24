# frozen_string_literal: true

module Resolvers
  class PlanAppliedRateCardsResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization
    include RateCardListArguments

    REQUIRED_PERMISSION = "plans:view"

    description "Query rate cards applied to a plan"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :plan_id, ID, required: false

    type Types::PlanAppliedRateCards::Object.collection_type, null: false

    def resolve(plan_id: nil, page: nil, limit: nil, search_term: nil, **filters)
      result = ::PlanRateCardsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: filters.merge(plan_id:),
        search_term:,
        order: :product_category
      )

      result.plan_rate_cards
    end
  end
end
