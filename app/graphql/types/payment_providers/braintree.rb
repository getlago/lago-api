# frozen_string_literal: true

module Types
  module PaymentProviders
    class Braintree < Types::BaseObject
      graphql_name "BraintreeProvider"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false

      field :merchant_id, String, null: false, permission: "organization:integrations:view"
      field :private_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :public_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"
    end
  end
end
