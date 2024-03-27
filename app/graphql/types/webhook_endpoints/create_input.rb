# frozen_string_literal: true

module Types
  module WebhookEndpoints
    class CreateInput < BaseInputObject
      graphql_name "WebhookEndpointCreateInput"

      argument :signature_algo, Types::WebhookEndpoints::SignatureAlgoEnum, required: false
      argument :webhook_url, String, required: true
    end
  end
end
