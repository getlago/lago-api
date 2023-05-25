# frozen_string_literal: true

module Types
  module Invoices
    class Usage < Types::BaseObject
      graphql_name 'CustomerUsage'

      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false

      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, GraphQL::Types::BigInt, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false

      field :charges_usage, [Types::Charges::Usage], null: false, method: :fees
    end
  end
end
