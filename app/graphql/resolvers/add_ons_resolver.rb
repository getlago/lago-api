# frozen_string_literal: true

module Resolvers
  class AddOnsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'addons:view'

    description 'Query add-ons of an organization'

    argument :ids, [ID], required: false, description: 'List of add-ons IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::AddOns::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, search_term: nil)
      query = ::AddOnsQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:
        },
      )

      result.add_ons
    end
  end
end
