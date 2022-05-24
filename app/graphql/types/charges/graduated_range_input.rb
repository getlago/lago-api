# frozen_string_literal: true

module Types
  module Charges
    class GraduatedRangeInput < Types::BaseInputObject
      graphql_name 'GraduatedRangeInput'

      argument :from_value, Integer, required: true
      argument :to_value, Integer, required: false

      argument :per_unit_amount, String, required: true
      argument :flat_amount, String, required: true
    end
  end
end
