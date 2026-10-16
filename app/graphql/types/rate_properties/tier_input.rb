# frozen_string_literal: true

module Types
  module RateProperties
    class TierInput < Types::BaseInputObject
      graphql_name "RateTierInput"
      description "Graduated or volume tier of a catalog rate, starting where the previous tier ends"

      argument :to_value, String, required: false, description: "Upper bound of the tier; null on the last tier"

      argument :flat_amount, String, required: true
      argument :per_unit_amount, String, required: true
    end
  end
end
