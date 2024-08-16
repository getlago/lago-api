# frozen_string_literal: true

module Types
  module PaymentRequests
    class Object < Types::BaseObject
      graphql_name "PaymentRequest"

      field :id, ID, null: false

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :email, String, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :customer, Types::Customers::Object, null: false
      field :invoices, [Types::Invoices::Object], null: false
    end
  end
end
