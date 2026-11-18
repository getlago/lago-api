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

      if include?(:signing_keys)
        payload.merge(signing_keys:)
      else
        payload
      end
    end

    private

    def signing_keys
      model.exposed_signing_keys.map do |signing_key|
        {
          lago_id: signing_key.id,
          secret_key: signing_key.secret,
          created_at: signing_key.created_at.iso8601
        }
      end
    end
  end
end
