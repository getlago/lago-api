# frozen_string_literal: true

module Resolvers
  class WebhookEndpointResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single webhook endpoint'

    argument :id, ID, required: true, description: 'Uniq ID of the webhook endpoint'

    type Types::WebhookEndpoints::Object, null: true

    def resolve(id:)
      validate_organization!

      current_organization.webhook_endpoints.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'webhook_endpoint')
    end
  end
end
