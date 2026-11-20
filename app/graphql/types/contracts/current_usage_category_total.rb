# frozen_string_literal: true

module Types
  module Contracts
    class CurrentUsageCategoryTotal < Types::BaseObject
      graphql_name "ContractCurrentUsageCategoryTotal"
      description "The share of a contract's current usage total priced by one product category"

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false,
        description: "Earliest billing window start across the category's rate cards"
      field :product_category, Types::ProductCategories::Object, null: true,
        description: "Null for the products that belong to no category"
      field :taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false,
        description: "Latest billing window end across the category's rate cards"
      field :total_amount_cents, GraphQL::Types::BigInt, null: false
    end
  end
end
