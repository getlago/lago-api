# frozen_string_literal: true

module Types
  module RateCardRates
    class UpdateInput < BaseInputObject
      description "Update rate card rate input arguments"

      argument :id, ID, required: true

      argument :applied_pricing_unit_conversion_rate, GraphQL::Types::Float, required: false
      argument :billing_interval_count, Integer, required: false
      argument :billing_interval_unit, Types::RateCardRates::BillingIntervalUnitEnum, required: false
      argument :effective_datetime, GraphQL::Types::ISO8601DateTime, required: false
      argument :min_amount_cents, GraphQL::Types::BigInt, required: false
      argument :rate_model, Types::RateCardRates::RateModelEnum, required: false
      argument :rate_properties, GraphQL::Types::JSON, required: false
    end
  end
end
