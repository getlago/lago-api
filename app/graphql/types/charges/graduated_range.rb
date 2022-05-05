# frozen_string_literal: true

module Types
  module Charges
    class GraduatedRange < Types::BaseObject
      graphql_name 'GraduatedRange'

      field :from_value, Integer, null: false
      field :to_value, Integer, null: true
      field :to_infinity, Boolean, null: false

      field :per_unit_price_amount_cents, Integer, null: false
      field :per_unit_price_amount_currency, Types::CurrencyEnum, null: false

      field :flat_amount_cents, Integer, null: false
      field :flat_amount_currency, Types::CurrencyEnum, null: false
    end
  end
end
