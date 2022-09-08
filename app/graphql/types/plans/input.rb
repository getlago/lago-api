# frozen_string_literal: true

module Types
  module Plans
    class Input < Types::BaseInputObject
      graphql_name 'PlanInput'

      argument :name, String, required: true
      argument :code, String, required: true
      argument :interval, Types::Plans::IntervalEnum, required: true
      argument :pay_in_advance, Boolean, required: true
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum
      argument :trial_period, Float, required: false
      argument :description, String, required: false
      argument :bill_charges_monthly, Boolean, required: false

      argument :charges, [Types::Charges::Input]
    end
  end
end
