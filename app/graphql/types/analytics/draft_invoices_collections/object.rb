# frozen_string_literal: true

module Types
  module Analytics
    module DraftInvoicesCollections
      class Object < Types::BaseObject
        graphql_name "DraftInvoicesCollection"

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :currency, Types::CurrencyEnum, null: true
        field :invoices_count, GraphQL::Types::BigInt, null: false
        field :month, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
