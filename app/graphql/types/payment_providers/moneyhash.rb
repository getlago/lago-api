# frozen_string_literal: true

module Types
  module PaymentProviders
    class Moneyhash < Types::BaseObject
      graphql_name "MoneyhashProvider"

      field :api_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :code, String, null: false
      field :flow_id, String, null: true, permission: "organization:integrations:view"
      field :id, ID, null: false
      field :name, String, null: false
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"
    end
  end
end
