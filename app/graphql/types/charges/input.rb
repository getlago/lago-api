# frozen_string_literal: true

module Types
  module Charges
    class Input < Types::BaseInputObject
      graphql_name 'ChargeInput'

      argument :id, ID, required: false
      argument :billable_metric_id, ID, required: true
      argument :charge_model, Types::Charges::ChargeModelEnum, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true

      # NOTE: Standard charge model
      argument :amount_cents, Integer, required: false

      # NOTE: Graduated charge model
      argument :graduated_ranges, [Types::Charges::GraduatedRangeInput], required: false
    end
  end
end
