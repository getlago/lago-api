# frozen_string_literal: true

module Types
  module Charges
    class GraduatedRange < Types::BaseObject
      graphql_name 'GraduatedRange'

      field :from_value, Integer, null: false
      field :to_value, Integer, null: true

      field :per_unit_amount_cents, Integer, null: false
      field :flat_amount_cents, Integer, null: false
    end
  end
end
