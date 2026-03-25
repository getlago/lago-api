# frozen_string_literal: true

module Types
  module Customers
    class CreditNotesBalance < Types::BaseObject
      graphql_name "CustomerCreditNotesBalance"

      field :currency, Types::CurrencyEnum, null: false
      field :amount_cents, GraphQL::Types::BigInt, null: false
    end
  end
end
