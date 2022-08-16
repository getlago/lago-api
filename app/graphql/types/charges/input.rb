# frozen_string_literal: true

module Types
  module Charges
    class Input < Types::BaseInputObject
      graphql_name 'ChargeInput'

      argument :id, ID, required: false
      argument :billable_metric_id, ID, required: true
      argument :charge_model, Types::Charges::ChargeModelEnum, required: true
      argument :amount_currency, Types::CurrencyEnum, required: true

      # NOTE: Standard and Package charge model
      argument :amount, String, required: false

      # NOTE: Graduated charge model
      argument :graduated_ranges, [Types::Charges::GraduatedRangeInput], required: false

      # NOTE: Package charge model
      argument :free_units, Integer, required: false
      argument :package_size, Integer, required: false

      # NOTE: Percentage charge model
      argument :rate, String, required: false
      argument :fixed_amount, String, required: false
    end
  end
end
