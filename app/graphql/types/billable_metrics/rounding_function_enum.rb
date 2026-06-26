# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module BillableMetrics
    class RoundingFunctionEnum < Types::BaseEnum
      BillableMetric::ROUNDING_FUNCTIONS.values.each do |type|
        value type
      end
    end
  end
end
