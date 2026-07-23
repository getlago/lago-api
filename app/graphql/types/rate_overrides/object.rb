# frozen_string_literal: true

module Types
  module RateOverrides
    class Object < Types::BaseObject
      graphql_name "RateOverride"
      description "Overridden pricing applied by a rate phase in place of the card's active rate"

      field :billing_interval_count, Integer, null: true
      field :billing_interval_unit, Types::RateCardRates::BillingIntervalUnitEnum, null: true
      field :id, ID, null: false
      field :min_amount_cents, GraphQL::Types::BigInt, null: false
      field :pricing_unit_conversion_rate, GraphQL::Types::Float, null: true
      field :rate_model, Types::RateCardRates::RateModelEnum, null: false
      field :rate_properties, GraphQL::Types::JSON, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
