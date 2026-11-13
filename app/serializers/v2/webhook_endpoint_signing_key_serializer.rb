# frozen_string_literal: true

module V2
  class WebhookEndpointSigningKeySerializer < ModelSerializer
    timestamps :created_at

    def serialize = {lago_id: model.id, secret_key: model.secret}
  end
end
