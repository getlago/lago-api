# frozen_string_literal: true

module V2
  class WebhookEndpointSerializer < ModelSerializer
    timestamps :created_at, :updated_at

    # Never `webhooks: true`: the keys must not reach a webhook body.
    expandable :signing_keys, serializer: ::V2::WebhookEndpointSigningKeySerializer

    def serialize
      {
        lago_id: model.id,
        name: model.name,
        webhook_url: model.webhook_url,
        signature_algo: model.signature_algo,
        event_types: model.event_types
      }
    end

    private

    def signing_keys = model.exposed_signing_keys
  end
end
