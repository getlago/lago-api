# frozen_string_literal: true

module Types
  module RateCardRates
    class Object < Types::BaseObject
      graphql_name "RateCardRate"
      description "An effective-dated pricing entry of a rate card"

      field :id, ID, null: false

      field :effective_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :status, Types::RateCardRates::StatusEnum, null: false

      field :rate_model, Types::RateCardRates::RateModelEnum, null: false
      field :rate_properties, GraphQL::Types::JSON, null: false

      field :applied_pricing_unit_conversion_rate, GraphQL::Types::Float, null: true
      field :billing_interval_count, Integer, null: false
      field :billing_interval_unit, Types::RateCardRates::BillingIntervalUnitEnum, null: false
      field :min_amount_cents, GraphQL::Types::BigInt, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
