# frozen_string_literal: true

module Types
  module ChargeModels
    class GraduatedPercentageRange < Types::BaseObject
      field :from_value, GraphQL::Types::BigInt, null: false
      field :to_value, GraphQL::Types::BigInt, null: true

      field :flat_amount, String, null: false
      field :rate, String, null: false
    end
  end
end
