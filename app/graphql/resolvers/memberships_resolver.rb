# frozen_string_literal: true

module Resolvers
  class MembershipsResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query memberships of an organization'

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::MembershipType.collection_type, null: false

    def resolve(page: nil, limit: nil)
      validate_organization!

      current_organization
        .memberships
        .active
        .page(page)
        .per(limit)
    end
  end
end
