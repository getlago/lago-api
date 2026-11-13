# frozen_string_literal: true

module Types
  module WebhookEndpoints
    class SigningKeyObject < Types::BaseObject
      graphql_name "WebhookEndpointSigningKey"

      field :id, ID, null: false
      field :secret_key, String, null: false, method: :secret

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
