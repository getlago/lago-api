# frozen_string_literal: true

module Resolvers
  class WebhooksResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "developers:manage"

    description "Query Webhooks"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false
    argument :status, Types::Webhooks::StatusEnum, required: false
    argument :webhook_endpoint_id, String, required: true

    type Types::Webhooks::Object.collection_type, null: false

    def resolve(webhook_endpoint_id:, page: nil, limit: nil, status: nil, search_term: nil)
      result = WebhooksQuery.call(
        organization: current_organization,
        search_term:,
        filters: {
          webhook_endpoint_id:,
          status:
        },
        pagination: {
          page:,
          limit:
        }
      )

      result.webhooks
    end
  end
end
