# frozen_string_literal: true

module Types
  module RateProperties
    class PercentageTierInput < Types::BaseInputObject
      graphql_name "RatePercentageTierInput"
      description "Graduated percentage tier of a catalog rate, starting where the previous tier ends"

      argument :to_value, String, required: false, description: "Upper bound of the tier; null on the last tier"

      argument :flat_amount, String, required: true
      argument :rate, String, required: true
    end
  end
end
