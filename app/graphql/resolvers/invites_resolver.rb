# frozen_string_literal: true

module Resolvers
  class InvitesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query pending invites of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :search_term, String, required: false

    argument :role_ids, [ID], required: false

    type Types::Invites::Object.collection_type, null: false

    def resolve(search_term: nil, page: nil, limit: nil, **filters)
      result = InvitesQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {
          page:,
          limit:
        },
        filters:
      )

      result.invites
    end
  end
end
