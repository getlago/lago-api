# frozen_string_literal: true

module Resolvers
  class SelectablePlansResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = %w[coupons:view coupons:update wallets:create wallets:update]

    description "Query plans of an organization for selection inputs"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::Plans::SelectableObject.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil)
      result = PlansQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {page:, limit:}
      )

      result.plans
    end
  end
end
