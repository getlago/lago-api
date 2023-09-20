# frozen_string_literal: true

module Types
  module Subscriptions
    class PlanOverridesInput < Types::BaseInputObject
      argument :amount_cents, GraphQL::Types::BigInt
      argument :amount_currency, Types::CurrencyEnum
      argument :charges, [Types::Subscriptions::ChargeOverridesInput]
      argument :invoice_display_name, String
      argument :tax_codes, [String]
      argument :trial_period, Float
    end
  end
end
