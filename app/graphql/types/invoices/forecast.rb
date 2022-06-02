# frozen_string_literal: true

module Types
  module Invoices
    class Forecast < Types::BaseObject
      graphql_name 'Forecast'

      field :from_date, GraphQL::Types::ISO8601Date, null: false
      field :to_date, GraphQL::Types::ISO8601Date, null: false
      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :total_amount_cents, Integer, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, Integer, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false

      field :fees, [Types::Invoices::ForecastedFee], null: true
    end
  end
end
