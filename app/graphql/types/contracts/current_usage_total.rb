# frozen_string_literal: true

module Types
  module Contracts
    class CurrentUsageTotal < Types::BaseObject
      graphql_name "ContractCurrentUsageTotal"
      description "The contract's total computed usage for the current billing period, unfiltered"

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :taxes_amount_cents, GraphQL::Types::BigInt, null: false
      field :total_amount_cents, GraphQL::Types::BigInt, null: false
    end
  end
end
