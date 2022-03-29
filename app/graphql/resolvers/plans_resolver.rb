# frozen_string_literal: true

module Resolvers
  class PlansResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query plans of an organization'

    argument :ids, [String], required: false, description: 'List of plan ID to fetch'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::Plans::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil)
      validate_organization!

      plans = current_organization
        .plans
        .page(page)
        .per(limit)

      plans = plans.where(id: ids) if ids.present?

      plans
    end
  end
end
