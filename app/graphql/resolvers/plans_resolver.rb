# frozen_string_literal: true

module Resolvers
  class PlansResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query plans of an organization'

    argument :ids, [String], required: false, description: 'List of plan ID to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :search_term, String, required: false

    type Types::Plans::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, search_term: nil)
      validate_organization!

      query = PlanQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
        },
      )

      result.plans
    end
  end
end
