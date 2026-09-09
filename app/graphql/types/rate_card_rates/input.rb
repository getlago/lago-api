# frozen_string_literal: true

module Types
  module RateCardRates
    class Input < BaseInputObject
      graphql_name "RateCardRateInput"
      description "Rate card rate input arguments"

      argument :applied_pricing_unit_conversion_rate, GraphQL::Types::Float, required: false
      argument :billing_interval_count, Integer, required: false
      argument :billing_interval_unit, Types::RateCardRates::BillingIntervalUnitEnum, required: true
      argument :code, String, required: true
      argument :effective_from, GraphQL::Types::ISO8601DateTime, required: true
      argument :min_amount_cents, GraphQL::Types::BigInt, required: false
      argument :rate_model, Types::RateCardRates::RateModelEnum, required: true
      argument :rate_properties, Types::Charges::PropertiesInput, required: true
    end
  end
end
