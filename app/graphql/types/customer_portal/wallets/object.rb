# frozen_string_literal: true

module Types
  module CustomerPortal
    module Wallets
      class Object < Types::BaseObject
        graphql_name "CustomerPortalWallet"
        description "CustomerPortalWallet"

        field :id, ID, null: false

        field :currency, Types::CurrencyEnum, null: false
        field :expiration_at, GraphQL::Types::ISO8601DateTime, null: true
        field :name, String, null: true
        field :status, Types::Wallets::StatusEnum, null: false

        field :balance_cents, GraphQL::Types::BigInt, null: false
        field :consumed_amount_cents, GraphQL::Types::BigInt, null: false
        field :consumed_credits, GraphQL::Types::Float, null: false
        field :credits_balance, GraphQL::Types::Float, null: false
        field :credits_ongoing_balance, GraphQL::Types::Float, null: false
        field :ongoing_balance_cents, GraphQL::Types::BigInt, null: false
        field :ongoing_usage_balance_cents, GraphQL::Types::BigInt, null: false
        field :rate_amount, GraphQL::Types::Float, null: false
      end
    end
  end
end
