# frozen_string_literal: true

module Types
  module Analytics
    module RevenueStreams
      class Object < Types::BaseObject
        graphql_name "RevenueStreams"

        field :amount_currency, Types::CurrencyEnum, null: true

        field :coupons_amount_cents, GraphQL::Types::BigInt, null: false
        field :gross_revenue_amount_cents, GraphQL::Types::BigInt, null: false
        field :net_revenue_amount_cents, GraphQL::Types::BigInt, null: false

        field :commitment_fee_amount_cents, GraphQL::Types::BigInt, null: false
        field :in_advance_fee_amount_cents, GraphQL::Types::BigInt, null: false
        field :one_off_fee_amount_cents, GraphQL::Types::BigInt, null: false
        field :subscription_fee_amount_cents, GraphQL::Types::BigInt, null: false
        field :usage_based_fee_amount_cents, GraphQL::Types::BigInt, null: false

        field :end_of_period_dt, GraphQL::Types::ISO8601Date, null: false
        field :start_of_period_dt, GraphQL::Types::ISO8601Date, null: false
      end
    end
  end
end
