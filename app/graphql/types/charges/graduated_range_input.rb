# frozen_string_literal: true

module Types
  module Charges
    class GraduatedRangeInput < Types::BaseInputObject
      graphql_name 'GraduatedRangeInput'

      argument :from_value, Integer, required: true
      argument :to_value, Integer, required: false
      argument :to_infinity, Boolean, required: true

      argument :per_unit_price_amount_cents, Integer, required: true
      argument :per_unit_price_amount_currency, Types::CurrencyEnum, required: true

      argument :flat_amount_cents, Integer, required: true
      argument :flat_amount_currency, Types::CurrencyEnum, required: true
    end
  end
end
