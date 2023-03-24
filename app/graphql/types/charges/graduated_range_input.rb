# frozen_string_literal: true

module Types
  module Charges
    class GraduatedRangeInput < Types::BaseInputObject
      argument :from_value, GraphQL::Types::BigInt, required: true
      argument :to_value, GraphQL::Types::BigInt, required: false

      argument :per_unit_amount, String, required: true
      argument :flat_amount, String, required: true
    end
  end
end
