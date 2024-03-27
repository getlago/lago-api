# frozen_string_literal: true

module Types
  module WalletTransactions
    class Object < Types::BaseObject
      graphql_name "WalletTransaction"

      field :id, ID, null: false
      field :wallet, Types::Wallets::Object

      field :amount, String, null: false
      field :credit_amount, String, null: false
      field :status, Types::WalletTransactions::StatusEnum, null: false
      field :transaction_type, Types::WalletTransactions::TransactionTypeEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :settled_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
