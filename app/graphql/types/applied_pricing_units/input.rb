# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module AppliedPricingUnits
    class Input < Types::BaseInputObject
      graphql_name "AppliedPricingUnitInput"

      argument :code, String, required: true
      argument :conversion_rate, GraphQL::Types::Float, required: true
    end
  end
end
