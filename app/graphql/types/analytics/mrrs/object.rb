# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Analytics
    module Mrrs
      class Object < Types::BaseObject
        graphql_name "Mrr"

        field :amount_cents, GraphQL::Types::BigInt, null: true
        field :currency, Types::CurrencyEnum, null: true
        field :month, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
