# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Analytics
    module InvoicedUsages
      class Object < Types::BaseObject
        graphql_name "InvoicedUsage"

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :code, String, null: true
        field :currency, Types::CurrencyEnum, null: false
        field :month, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
