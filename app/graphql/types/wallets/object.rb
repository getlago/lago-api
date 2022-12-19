# frozen_string_literal: true

module Types
  module Wallets
    class Object < Types::BaseObject
      graphql_name 'Wallet'

      field :id, ID, null: false
      field :customer, Types::Customers::Object

      field :name, String, null: true
      field :status, Types::Wallets::StatusEnum, null: false
      field :rate_amount, String, null: false
      field :currency, Types::CurrencyEnum, null: false
      field :credits_balance, String, null: false
      field :balance, String, null: false
      field :consumed_amount, String, null: false
      field :consumed_credits, String, null: false

      field :expiration_at, GraphQL::Types::ISO8601DateTime, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :terminated_at, GraphQL::Types::ISO8601DateTime, null: true
      field :last_balance_sync_at, GraphQL::Types::ISO8601DateTime, null: true
      field :last_consumed_credit_at, GraphQL::Types::ISO8601DateTime, null: true
    end
  end
end
