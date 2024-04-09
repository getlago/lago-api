# frozen_string_literal: true

module Resolvers
  class WebhookEndpointsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query webhook endpoints of an organization'

    argument :ids, [ID], required: false, description: 'List of webhook endpoint IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::WebhookEndpoints::Object.collection_type, null: false

    def resolve(ids: nil, page: nil, limit: nil, search_term: nil)
      query = ::WebhookEndpointsQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        filters: {
          ids:,
        },
      )

      result.webhook_endpoints
    end
  end
end
