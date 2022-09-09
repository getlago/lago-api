# frozen_string_literal: true

module Resolvers
  class InvitesResolver < GraphQL::Schema::Resolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query pending invites of an organization'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false

    type Types::Invites::Object.collection_type, null: false

    def resolve(page: nil, limit: nil)
      validate_organization!

      current_organization
        .invites
        .pending
        .page(page)
        .per(limit)
    end
  end
end