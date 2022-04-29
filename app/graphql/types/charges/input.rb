# frozen_string_literal: true

module Types
  module Charges
    class Input < Types::BaseInputObject
      graphql_name 'ChargeInput'

      argument :id, ID, required: false
      argument :billable_metric_id, ID, required: true
      argument :amount_cents, Integer, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true
      argument :charge_model, Types::Charges::ChargeModelEnum, required: true
    end
  end
end
