# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module WebhookEndpoints
    class EventTypeEnum < Types::BaseEnum
      WebhookEndpoint::WEBHOOK_EVENT_TYPE_CONFIG.each do |key, event_type|
        value key.to_s, value: event_type[:name]
      end
      # special case for "all" event type which is not in the config but is a valid event type
      value "all", value: "*"
    end
  end
end
