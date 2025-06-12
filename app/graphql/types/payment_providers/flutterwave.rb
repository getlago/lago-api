# frozen_string_literal: true

module Types
  module PaymentProviders
    class Flutterwave < Types::BaseObject
      graphql_name "FlutterwaveProvider"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false

      field :encryption_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :production, Boolean, null: true, permission: "organization:integrations:view"
      field :public_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :secret_key, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :success_redirect_url, String, null: true, permission: "organization:integrations:view"
    end
  end
end
