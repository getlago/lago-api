# frozen_string_literal: true

module Types
  module Subscriptions
    class PlanOverridesInput < Types::BaseInputObject
      argument :amount_cents, GraphQL::Types::BigInt, required: false
      argument :amount_currency, Types::CurrencyEnum, required: false
      argument :charges, [Types::Subscriptions::ChargeOverridesInput], required: false
      argument :description, String, required: false
      argument :invoice_display_name, String, required: false
      argument :minimum_commitment, Types::Commitments::Input, required: false
      argument :name, String, required: false
      argument :tax_codes, [String], required: false
      argument :trial_period, Float, required: false
      argument :usage_thresholds, [Types::Subscriptions::UsageThresholdOverridesInput], required: false
    end
  end
end
