# frozen_string_literal: true

module Types
  module Invoices
    class Usage < Types::BaseObject
      graphql_name 'CustomerUsage'

      field :from_date, GraphQL::Types::ISO8601Date, null: false
      field :to_date, GraphQL::Types::ISO8601Date, null: false
      field :issuing_date, GraphQL::Types::ISO8601Date, null: false

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, GraphQL::Types::BigInt, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false

      field :charges_usage, [Types::Charges::Usage], null: false

      def charges_usage
        object.fees
      end
    end
  end
end
