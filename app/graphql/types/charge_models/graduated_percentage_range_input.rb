# frozen_string_literal: true

module Types
  module ChargeModels
    class GraduatedPercentageRangeInput < Types::BaseInputObject
      argument :from_value, GraphQL::Types::BigInt, required: true
      argument :to_value, GraphQL::Types::BigInt, required: false

      argument :flat_amount, String, required: true
      argument :rate, String, required: true
    end
  end
end
