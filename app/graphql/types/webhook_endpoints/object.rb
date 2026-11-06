# frozen_string_literal: true

module Types
  module WebhookEndpoints
    class Object < Types::BaseObject
      graphql_name "WebhookEndpoint"

      field :event_types, [Types::WebhookEndpoints::EventTypeEnum], null: true
      field :id, ID, null: false
      field :name, String, null: true
      field :organization, Types::Organizations::OrganizationType
      field :signature_algo, Types::WebhookEndpoints::SignatureAlgoEnum
      field :signing_keys, [Types::WebhookEndpoints::SigningKeyObject], permission: "developers:keys:manage"
      field :webhook_url, String, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # An allow-list: only the paths that return one endpoint set the flag, so lists and webhook logs never show keys.
      def signing_keys
        if context[:expose_webhook_signing_keys]
          object.listed_signing_keys
        end
      end
    end
  end
end
