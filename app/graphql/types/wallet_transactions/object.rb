# frozen_string_literal: true

module Types
  module WalletTransactions
    class Object < Types::BaseObject
      graphql_name 'WalletTransaction'

      field :id, ID, null: false
      field :wallet, Types::Wallets::Object

      field :transaction_type, Types::WalletTransactions::TransactionTypeEnum, null: false
      field :status, Types::Wallets::StatusEnum, null: false
      field :amount, String, null: false
      field :credit_amount, String, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :settled_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
