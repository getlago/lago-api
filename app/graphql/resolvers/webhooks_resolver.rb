# frozen_string_literal: true

module Resolvers
  class WebhooksResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query Webhooks'

    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :status, Types::Webhooks::StatusEnum, required: false
    argument :search_term, String, required: false

    type Types::Webhooks::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, status: nil, search_term: nil)
      validate_organization!

      query = WebhooksQuery.new(organization: current_organization)
      result = query.call(
        search_term:,
        page:,
        limit:,
        status:,
      )

      result.webhooks
    end
  end
end
