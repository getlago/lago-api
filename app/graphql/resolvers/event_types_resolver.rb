# frozen_string_literal: true

module Resolvers
  class EventTypesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser

    REQUIRED_PERMISSION = "developers:manage"

    description "Query Event Types for Webhook Endpoints"

    type [Types::WebhookEndpoints::EventType], null: false

    def resolve
      WEBHOOK_EVENT_TYPES.values
    end
  end
end
