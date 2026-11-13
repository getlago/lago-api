# frozen_string_literal: true

module Types
  module X402
    class Connection < Types::BaseObject
      graphql_name "X402ConnectionObject"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false

      field :allowed_origins, [String], null: false
      field :asset, Types::X402::AssetEnum, null: false
      field :auto_create_customers, Boolean, null: false
      field :cdp_api_key_id, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :cdp_api_key_secret, ObfuscatedStringType, null: true, permission: "organization:integrations:view"
      field :facilitator, Types::X402::FacilitatorEnum, null: false
      field :networks, [String], null: false
      field :payout_addresses, Types::X402::PayoutAddresses, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
