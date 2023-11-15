# frozen_string_literal: true

module Types
  module Wallets
    class Object < Types::BaseObject
      graphql_name 'Wallet'
      description 'Wallet'

      field :id, ID, null: false

      field :customer, Types::Customers::Object

      field :currency, Types::CurrencyEnum, null: false
      field :name, String, null: true
      field :status, Types::Wallets::StatusEnum, null: false

      field :rate_amount, GraphQL::Types::Float, null: false

      field :balance_cents, GraphQL::Types::BigInt, null: false
      field :consumed_amount_cents, GraphQL::Types::BigInt, null: false

      field :consumed_credits, GraphQL::Types::Float, null: false
      field :credits_balance, GraphQL::Types::Float, null: false

      field :last_balance_sync_at, GraphQL::Types::ISO8601DateTime, null: true
      field :last_consumed_credit_at, GraphQL::Types::ISO8601DateTime, null: true

      field :recurring_transaction_rules, [Types::Wallets::RecurringTransactionRules::Object], null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :expiration_at, GraphQL::Types::ISO8601DateTime, null: true
      field :terminated_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
