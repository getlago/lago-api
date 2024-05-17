# frozen_string_literal: true

module V1
  class WebhookEndpointSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_organization_id: model.organization_id,
        webhook_url: model.webhook_url,
        signature_algo: model.signature_algo
      }
    end
  end
end
