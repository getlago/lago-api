# frozen_string_literal: true

module Types
  module Invoices
    class Object < Types::BaseObject
      graphql_name 'Invoice'

      field :id, ID, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :total_amount_cents, Integer, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, Integer, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false

      field :from_date, GraphQL::Types::ISO8601Date, null: false
      field :to_date, GraphQL::Types::ISO8601Date, null: false
      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :subscription, Types::Subscriptions::Object
      field :plan, Types::Plans::Object
    end
  end
end
