# frozen_string_literal: true

module Resolvers
  class MembershipsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query memberships of an organization"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    argument :search_term, String, required: false

    argument :role_ids, [ID], required: false

    type Types::MembershipType.collection_type(metadata_type: Types::Memberships::Metadata), null: false

    def resolve(search_term: nil, page: nil, limit: nil, **filters)
      result = MembershipsQuery.call(
        organization: current_organization,
        search_term:,
        pagination: {
          page:,
          limit:
        },
        filters:
      )

      result.memberships.includes(:user)
    end
  end
end
