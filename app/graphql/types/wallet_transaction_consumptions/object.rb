# frozen_string_literal: true

module Types
  module WalletTransactionConsumptions
    class Object < Types::BaseObject
      graphql_name "WalletTransactionConsumption"

      field :amount_cents, GraphQL::Types::BigInt, null: false, method: :consumed_amount_cents
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :id, ID, null: false
      field :inbound_wallet_transaction, Types::WalletTransactions::Object, null: false
      field :outbound_wallet_transaction, Types::WalletTransactions::Object, null: false
    end
  end
end
