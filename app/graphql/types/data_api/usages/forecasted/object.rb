# frozen_string_literal: true

module Types
  module DataApi
    module Usages
      module Forecasted
        class Object < Types::BaseObject
          graphql_name "DataApiUsageForecasted"

          field :amount_cents, GraphQL::Types::BigInt, null: false
          field :amount_cents_forecast_10th_percentile, GraphQL::Types::BigInt, null: false
          field :amount_cents_forecast_50th_percentile, GraphQL::Types::BigInt, null: false
          field :amount_cents_forecast_90th_percentile, GraphQL::Types::BigInt, null: false
          field :amount_currency, Types::CurrencyEnum, null: false

          field :units, Float, null: false
          field :units_forecast_10th_percentile, Float, null: false
          field :units_forecast_50th_percentile, Float, null: false
          field :units_forecast_90th_percentile, Float, null: false

          field :end_of_period_dt, GraphQL::Types::ISO8601Date, null: false
          field :start_of_period_dt, GraphQL::Types::ISO8601Date, null: false
        end
      end
    end
  end
end
