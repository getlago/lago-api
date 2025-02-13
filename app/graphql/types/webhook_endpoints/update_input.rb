# frozen_string_literal: true

module Types
  module WebhookEndpoints
    class UpdateInput < BaseInputObject
      graphql_name "WebhookEndpointUpdateInput"

      argument :id, ID, required: true
      argument :signature_algo, Types::WebhookEndpoints::SignatureAlgoEnum, required: false
      argument :webhook_url, String, required: true
    end
  end
end
