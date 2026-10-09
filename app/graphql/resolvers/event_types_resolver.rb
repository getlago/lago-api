# frozen_string_literal: true

module Resolvers
  class EventTypesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser

    REQUIRED_PERMISSION = "developers:manage"

    description "Query Event Types for Webhook Endpoints"

    type [Types::WebhookEndpoints::EventType], null: false

    def resolve
      event_types = WebhookEndpoint::WEBHOOK_EVENT_TYPE_CONFIG
      unless context[:current_organization]&.product_catalog_enabled?
        event_types = event_types.reject { |_, event_type| event_type[:product_catalog_only] }
      end

      event_types.map do |_, event_type|
        {
          key: event_type[:name],
          name: event_type[:name],
          description: event_type[:description],
          category: event_type[:category],
          deprecated: event_type[:deprecated]
        }
      end
    end
  end
end
