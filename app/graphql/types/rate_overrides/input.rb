# frozen_string_literal: true

module Types
  module RateOverrides
    class Input < BaseInputObject
      graphql_name "RateOverrideInput"
      description "Overridden pricing for a rate phase"

      argument :billing_interval_count, Integer, required: false
      argument :billing_interval_unit, Types::RateCardRates::BillingIntervalUnitEnum, required: false
      argument :min_amount_cents, GraphQL::Types::BigInt, required: false
      argument :pricing_unit_conversion_rate, GraphQL::Types::Float, required: false
      argument :rate_model, Types::RateCardRates::RateModelEnum, required: true
      argument :rate_properties, GraphQL::Types::JSON, required: true
    end
  end
end
