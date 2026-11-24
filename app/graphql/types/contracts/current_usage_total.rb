# frozen_string_literal: true

module Types
  module Contracts
    class CurrentUsageTotal < Types::BaseObject
      graphql_name "ContractCurrentUsageTotal"
      description "The contract's total computed usage for the current billing period, unfiltered"

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true,
        description: "Earliest billing window start across the contract's rate cards, null with no usage"
      field :product_category_totals, [Types::Contracts::CurrentUsageCategoryTotal], null: false,
        description: "The total split by product category, each one priced and taxed in the same pass as the total"
      field :taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :taxes_unavailable, Boolean, null: false,
        description: "True when the tax provider failed and amount/total above are the untaxed fallback"
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true,
        description: "Latest billing window end across the contract's rate cards, null with no usage"
      field :total_amount_cents, GraphQL::Types::BigInt, null: false
    end
  end
end
