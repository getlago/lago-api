# frozen_string_literal: true

module Resolvers
  class PlanProductItemsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "plans:view"

    description "Query product items assigned to a plan"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :plan_id, ID, required: false

    type Types::PlanProductItems::Object.collection_type, null: false

    def resolve(plan_id: nil, page: nil, limit: nil)
      result = ::PlanProductItemsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {plan_id:}
      )

      result.plan_product_items
    end
  end
end
