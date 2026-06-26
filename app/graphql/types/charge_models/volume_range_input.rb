# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module ChargeModels
    class VolumeRangeInput < Types::BaseInputObject
      argument :from_value, GraphQL::Types::BigInt, required: true
      argument :to_value, GraphQL::Types::BigInt, required: false

      argument :flat_amount, String, required: true
      argument :per_unit_amount, String, required: true
    end
  end
end
