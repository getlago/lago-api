# frozen_string_literal: true

module Types
  module RateProperties
    class Tier < Types::BaseObject
      graphql_name "RateTier"

      field :to_value, String, null: true

      field :flat_amount, String, null: false
      field :per_unit_amount, String, null: false
    end
  end
end
