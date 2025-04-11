# frozen_string_literal: true

module Types
  module Plans
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdatePlanInput"

      argument :id, ID, required: true

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true
      argument :bill_charges_monthly, Boolean, required: false
      argument :cascade_updates, Boolean, required: false
      argument :code, String, required: true
      argument :description, String, required: false
      argument :interval, Types::Plans::IntervalEnum, required: true
      argument :invoice_display_name, String, required: false
      argument :name, String, required: true
      argument :pay_in_advance, Boolean, required: true
      argument :tax_codes, [String], required: false
      argument :trial_period, Float, required: false

      argument :charges, [Types::Charges::Input]
      argument :minimum_commitment, Types::Commitments::Input, required: false
      argument :usage_thresholds, [Types::UsageThresholds::Input], required: false
    end
  end
end
