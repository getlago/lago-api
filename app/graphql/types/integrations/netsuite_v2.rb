# frozen_string_literal: true

module Types
  module Integrations
    class NetsuiteV2 < Types::BaseObject
      graphql_name "NetsuiteV2Integration"

      field :account_id, String, null: true
      field :client_id, String, null: true
      field :client_secret, ObfuscatedStringType, null: true
      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :script_endpoint_url, String, null: false
      field :sync_credit_notes, Boolean
      field :sync_invoices, Boolean
      field :sync_payments, Boolean
      field :token_id, String, null: true
      field :token_secret, ObfuscatedStringType, null: true
    end
  end
end
