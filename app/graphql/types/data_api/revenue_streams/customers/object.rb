# frozen_string_literal: true

module Types
  module DataApi
    module RevenueStreams
      module Customers
        class Object < Types::BaseObject
          graphql_name "DataApiRevenueStreamCustomer"

          field :customer_id, ID, null: false
          field :customer_name, String, null: false
          field :external_customer_id, String, null: false

          field :amount_currency, Types::CurrencyEnum, null: false
          field :gross_revenue_amount_cents, GraphQL::Types::BigInt, null: false
          field :gross_revenue_share, Float, null: false
          field :net_revenue_amount_cents, GraphQL::Types::BigInt, null: false
          field :net_revenue_share, Float, null: false
        end
      end
    end
  end
end
