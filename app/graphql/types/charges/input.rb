# frozen_string_literal: true

module Types
  module Charges
    class Input < Types::BaseInputObject
      graphql_name 'ChargeInput'

      argument :billable_metric_id, ID, required: true
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true
      argument :frequency, Types::Charges::FrequencyEnum, required: true
      argument :pro_rata, Boolean, required: true
      argument :vat_rate, Float, required: false
    end
  end
end
