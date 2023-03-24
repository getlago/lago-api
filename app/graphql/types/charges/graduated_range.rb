# frozen_string_literal: true

module Types
  module Charges
    class GraduatedRange < Types::BaseObject
      field :from_value, GraphQL::Types::BigInt, null: false
      field :to_value, GraphQL::Types::BigInt, null: true

      field :per_unit_amount, String, null: false
      field :flat_amount, String, null: false
    end
  end
end
