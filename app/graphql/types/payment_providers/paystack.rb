# frozen_string_literal: true

module Types
  module PaymentProviders
    class Paystack < Types::BaseObject
      graphql_name "PaystackProvider"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :secret_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"
    end
  end
end
