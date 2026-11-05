# frozen_string_literal: true

module V2
  class WebhookEndpointSerializer < ModelSerializer
    timestamps :created_at, :updated_at

    def serialize
      {
        lago_id: model.id,
        name: model.name,
        webhook_url: model.webhook_url,
        signature_algo: model.signature_algo,
        event_types: model.event_types
      }
    end
  end
end
