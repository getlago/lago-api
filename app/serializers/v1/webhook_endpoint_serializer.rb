# frozen_string_literal: true

module V1
  class WebhookEndpointSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_organization_id: model.organization_id,
        webhook_url: model.webhook_url,
        signature_algo: model.signature_algo,
        name: model.name,
        event_types: model.event_types,
        created_at: model.created_at.iso8601
      }

      # Opt-in: API logs store the response bodies of non-GET requests in clear.
      payload[:signing_keys] = signing_keys if include?(:signing_keys)
      payload
    end

    private

    def signing_keys
      model.active_signing_keys.map { ::V2::WebhookEndpoints::SigningKeySerializer.new(it).serialize }
    end
  end
end
