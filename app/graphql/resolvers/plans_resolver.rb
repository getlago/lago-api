# frozen_string_literal: true

module Resolvers
  class PlansResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query plans of an organization'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::Plans::Object.collection_type, null: false

    def resolve(page: nil, limit: nil)
      validate_organization!

      current_organization
        .plans
        .page(page)
        .per(limit)
    end
  end
end
